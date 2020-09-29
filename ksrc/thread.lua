-- port of the Monolith scheduler. this may not be the best but at least it's pretty reliable! --

do
  local thread, threads, sbuf, last, cur = {}, {}, {}, 0, 0
  local liveCoro = coroutine.create(function()end)

  local function checkDead(thd)
    local p = threads[thd.parent] or {dead = false, coro = liveCoro}
    if thd.dead or p.dead or coroutine.status(thd.coro) == "dead" or coroutine.status(p.coro) == "dead" then
      p = nil
      return true
    end
    p = nil
  end

  local function getMinTimeout()
    local min = math.huge
    for pid, thd in pairs(threads) do
      if thd.deadline - computer.uptime() < min then
        min = computer.uptime() - thd.deadline
      end
      if min <= 0 then
        min = 0
        break
      end
    end
    return min
  end

  local function cleanup()
    local dead = {}
    for pid, thd in pairs(threads) do
      if checkDead(thd) then
        for k, v in pairs(thd.closeOnExit) do
          local status,ret = pcall(v.close, v)
          if not status and ret then
            kio.dmesg(kio.loglevels.DEBUG, "handle failed to close on exit for thread '" .. pid .. ", " .. thd.name .. "' - " .. ret)
          end
        end
        computer.pushSignal("thread_died", pid)
        dead[#dead + 1] = pid
      end
    end
    for i=1, #dead, 1 do
      threads[dead[i]] = nil
    end

    local timeout = getMinTimeout()
    local sig = {computer.pullSignal(timeout)}
    if #sig > 0 then
      sbuf[#sbuf + 1] = sig
    end
  end

  local function getHandler(thd)
    return kio.dmesg
  end

  local function handleProcessError(thd, err)
    local h = getHandler(thd)
    threads[thd.pid] = nil
    computer.pushSignal("thread_errored", thd.pid, string.format("error in thread '%s' (PID %d): %s", thd.name, thd.pid, err))
    kio.dmesg("thread errored: " .. string.format("error in thread '%s' (PID %d): %s", thd.name, thd.pid, err))
    h(thd.name .. ": " .. err)
  end

  local global_env = {}

  function thread.spawn(func, name, priority, USER)
    checkArg(1, func, "function")
    checkArg(2, name, "string")
    checkArg(3, priority, "number", "nil")
    last = last + 1
    local current = thread.info() or { io = {stdin = {}, stdout = {}, stderr = {} }, env = {} }
    env = env or table.copy(current.env)
    local new = {
      coro = coroutine.create(func),            -- the thread
      pid = last,                               -- process/thread ID
      parent = cur,                             -- parent thread's PID
      name = name,                              -- thread name
      handlers = {},                            -- signal handlers
      owner = USER or k.security.users.user(),  -- current user
      sig = {},                                 -- signal buffer
      env = env,                                -- environment variables
      deadline = computer.uptime(),             -- signal deadline
      priority = priority,                      -- thread priority
      uptime = 0,                               -- thread uptime
      stopped = false,                          -- is it stopped?
      started = computer.uptime(),              -- time of thread creation
      closeOnExit = {},                         -- handles the scheduler should close on thread exit
      io      = {                               -- thread I/O streams
        stdin  = current.io.stdin,
        stdout = current.io.stdout,
        stderr = current.io.stderr or current.io.stdin
      }
    }
    new.closeOnExit[1] = new.io.stdin
    new.closeOnExit[2] = new.io.stdout
    new.closeOnExit[3] = new.io.stderr
    if not new.env.PWD then
      new.env.PWD = "/"
    end
    setmetatable(new, {__index = threads[cur] or {}})
    threads[last] = new
    computer.pushSignal("thread_spawned", last)
    return new
  end

  function thread.list()
    local t = {}
    for pid, _ in pairs(threads) do
      t[#t + 1] = pid
    end
    table.sort(t, function(a,b) return a < b end)
    return t
  end

  function thread.closeOnExit(handle)
    checkArg(1, handle, "table", "nil")
    local info, err = thread.info()
    if not info then return nil, err end
    local old = handle.close
    local i = #info.handles + 1
    function handle:close()
      info.handles[i] = nil
      return close()
    end
    info.handles[i] = handle
    return true
  end

  local temp = {}
  do
    local function stdstream(k)
      return function(self, file)
        checkArg(1, file, "table", "nil")
        if file and file.read and file.write and file.close then
          pcall(self.io[k].close, self.io[k])
          self.io[k] = file
        end
        return self.io[k]
      end
    end
    temp.stdin = stdstream('stdin')
    temp.stdout = stdstream('stdout')
    temp.stderr = stdstream('stderr')
  end

  function thread.getinfo(pid)
    checkArg(1, pid, "number", "nil")
    pid = pid or cur
    if not threads[pid] then
      return nil, "no such thread"
    end
    local t = threads[pid]
    local inf = {
      name = t.name,
      owner = t.owner,
      priority = t.priority,
      parent = t.parent,
      uptime = t.uptime,
      started = t.started,
      io = t.io,
      env = t.env,
      stdin = temp.stdin,
      stdout = temp.stdout,
      stderr = temp.stderr,
      handles = t.closeOnExit
    }
    return inf
  end
  thread.info = thread.getinfo

  function thread.signal(pid, sig)
    checkArg(1, pid, "number")
    checkArg(2, sig, "number")
    if not threads[pid] then
      return nil, "no such thread"
    end
    if threads[pid].owner ~= k.security.users.user() and k.security.users.user() ~= 0 then
      return nil, "permission denied"
    end
    local msg = {"signal", cur, sig}
    table.insert(threads[pid].sig, msg)
    return true
  end

  function thread.current()
    return cur
  end

  -- detach from the parent thread
  function thread.detach()
    threads[cur].parent = 1
  end

  -- detach any child thread, parent it to init
  function thread.orphan(pid)
    checkArg(1, pid, "number")
    if not threads[pid] then
      return nil, "no such thread"
    end
    if threads[pid].parent ~= cur then
      return nil, "specified thread is not a child of the current thread"
    end
    threads[pid].parent = 1 -- init
  end

  thread.signals = {
    interrupt = 2,
    INT       = 2,
    quit      = 3,
    QUIT      = 3,
    kill      = 9,
    KILL      = 9,
    term      = 15,
    TERM      = 15,
    terminate = 15,
    continue  = 18,
    CONT      = 18,
    stop      = 19,
    STOP      = 19,
    usr1      = 65,
    USR1      = 65,
    usr2      = 66,
    USR2      = 66
  }

  function thread.kill(pid, sig)
    return thread.signal(pid, sig or thread.signals.term)
  end

  function thread.loop()
    thread.start = nil
    while #threads > 0 do
      local run = {}
      for pid, thd in pairs(threads) do
        threads[pid].uptime = computer.uptime() - thd.started
        if (thd.deadline <= computer.uptime() or #sbuf > 0 or #thd.ipc > 0 or #thd.sig > 0) and not thd.stopped then
          run[#run + 1] = thd
        end
      end

      local sig = table.remove(sbuf, 1)
      table.sort(run, function(a, b)
        return a.priority < b.priority
      end)

      for i, thd in ipairs(run) do
        cur = thd.pid
        local ok, r1
        if #thd.sig > 0 then
          local nsig = table.remove(thd.sig, 1)
          if nsig[3] == thread.signals.kill then
            thd.dead = true
            ok, r1 = true, "killed"
          elseif nsig[3] == thread.signals.stop then
            thd.stopped = true
          elseif nsig[3] == thread.signals.continue then
            thd.stopped = false
          else
            ok, r1 = coroutine.resume(thd.coro, table.unpack(nsig))
          end
        elseif sig and #sig > 0 then
          ok, r1 = coroutine.resume(thd.coro, table.unpack(sig))
        else
          ok, r1 = coroutine.resume(thd.coro)
        end
        kio.dmesg(tostring(ok) .. " " .. tostring(r1))
        if (not ok) and r1 then
          handleProcessError(thd, r1)
        elseif ok then
          if r1 and type(r1) == "number" then
            thd.deadline = computer.uptime() + r1
          else
            thd.deadline = math.huge
          end
          thd.uptime = computer.uptime() - thd.started
        end
      end

      if computer.freeMemory() < 512 then -- oh no, we're out of memory
        kio.dmesg("Low memory - collecting garbage")
        collectgarbage()
        if computer.freeMemory() < 512 then -- GC didn't help. Panic!
          kio.panic("ran out of memory")
        end
      end
      cleanup()
    end
    kio.dmesg(kio.loglevels.WARNING, "thread: exited cleanly! this SHOULD NOT HAPPEN!")
    kio.panic("thread: all threads died!")
  end

  k.hooks.add("sandbox", function()
    -- userspace process api
    k.sb.process = {}
    k.sb.process.signals = k.sched.signals

    function k.sb.process.spawn(a,b,c)
      return k.sched.spawn(a,b,c).pid
    end

    function k.sb.process.info(pid)
      checkArg(1, pid, "number", "nil")
      local info, err = k.sched.getinfo(pid)
      if not info then
        return nil, err
      end
      local ret = {
        owner = info.owner,
        started = info.started,
        runtime = info.runtime,
        name = info.name
      }
      if pid == cur or not pid then
        ret.env = info.env
        ret.io = info.io
      end
      return ret
    end

    function k.sb.process.current()
      return cur
    end

    function k.sb.process.signal(pid, sig)
      return k.sched.signal(pid, sig)
    end

    function k.sb.process.thread(func, name)
      return k.sb.process.spawn(func, name)
    end
  end)
  k.process = {signals = thread.signals}
  k.sched = thread
end
