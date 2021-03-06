-- a scheduler! --

kio.dmesg(kio.loglevels.INFO, "ksrc/scheduler.lua")

do
  local procs = {}
  local s = {}
  local last, current = 0, 0

  -- k.sched.spawn(func:function, name:string[, priority:number]): table
  --   Spawns a process, adding `func` to its threads.
  function s.spawn(func, name, priority, iua)
    checkArg(1, func, "function")
    checkArg(2, name, "string")
    checkArg(3, priority, "number", "nil")
    last = last + 1
    local p = procs[current]
    local new = process.new {
      pid = last,
      name = name,
      parent = current,
      priority = priority or math.huge,
      env = p and table.copy(p.env) or {TERM="paragon"},
      stdin = p and io.input() or {},
      stdout = p and io.output() or {},
      stderr = p and io.stderr or {},
      owner = iua,
      sighandlers = {}
    }
    new.env.UID = new.owner
    new.env.USER = k.security.users.userByID(new.owner)
    new:addThread(func)
    procs[new.pid] = new
    return new -- the userspace function will just return the PID
  end

  -- k.sched.getinfo(pid:number): table or nil, string
  --   Returns information about a process.
  -- XXX: This function is dangerous and should not appear in userspace under
  -- XXX: any circumstances!
  function s.getinfo(pid)
    checkArg(1, pid, "number", "nil")
    pid = pid or current
    if not procs[pid] then
      return nil, "no such process"
    end
    return procs[pid]:info()
  end

  -- k.sched.signal(pid:number, sig:number): boolean or nil, string
  --   Attempts to kill process `pid` with signal `sig`.
  function s.signal(pid, sig)
    checkArg(1, pid, "number")
    checkArg(2, sig, "number")
    if not procs[pid] then
      return nil, "no such process"
    end
    local allow = k.security.acl.hasPermission(nil, "KILL_PROCESS")
    local proc = procs[pid]
    if allow and (proc.owner == s.getinfo().owner 
                  or s.getinfo().owner == 0) then
      proc:handle(sig)
    else
      return kio.error("PERMISSION_DENIED")
    end
  end

  function s.newthread(func, name)
    checkArg(1, func, "function")
    checkArg(2, name, "string", "nil")
    local proc = procs[current]
    if not proc then
      return nil, "error adding thread"
    end
    return proc:addThread(func, name)
  end

  s.kill = s.signal

  local function getMinTimeout()
    local max = math.huge
    local upt = computer.uptime()
    for pid, proc in pairs(procs) do
      if not proc.stopped then -- don't use timeouts from stopped processes
        if proc.deadline < 0 then
          max = 0
          break
        end
        if upt - proc.deadline < max then
          max = upt - proc.deadline
        end
        if max <= 0 then
          max = 0
          break
        end
      end
    end
    return max
  end

  function s.loop()
    s.loop = nil
    kio.dmesg(kio.loglevels.DEBUG, "starting scheduler loop")
    while #procs > 0 do
      local timeout = getMinTimeout()
      local sig = table.pack(computer.pullSignal(timeout))
      local run = {}
      for pid, proc in pairs(procs) do
        if not proc.stopped then
          run[#run + 1] = proc
        end
      end
      table.sort(run, function(a, b)
        return a.priority < b.priority
      end)
      for i=1, #run, 1 do
        local proc = run[i]
        current = proc.pid
        proc:resume(table.unpack(sig))
        if proc.dead then
          kio.dmesg(kio.loglevels.DEBUG, "process died: " .. proc.pid)
          computer.pushSignal("process_died", proc.pid, proc.name)
          for k,v in pairs(proc.handles) do
            pcall(v.close, v)
          end
          procs[proc.pid] = nil
        end
      end
      if computer.freeMemory() < 1024 then
        kio.dmesg(kio.loglevels.DEBUG, "low memory - collecting garbage")
        collectgarbage()
      end
    end
    kio.panic("All processes died!")
  end
  k.sched = s

  k.hooks.add("shutdown", function()
    kio.dmesg("sending SIGTERM to all processes")
    for pid, proc in pairs(procs) do
      proc:handle(process.signals.SIGTERM)
    end
    kio.dmesg("waiting 1s for processes to stop")
    local max = computer.uptime() + 1
    repeat
      computer.pullSignal(max - computer.uptime())
    until computer.uptime() >= max
    kio.dmesg("sending SIGKILL to all processes")
    for pid, proc in pairs(procs) do
      proc:handle(process.signals.SIGKILL)
    end
  end)

  do
    local prev_stopped, lID, lID2, slept
    k.hooks.add("sleep", function()
      prev_stopped = {}
      kio.dmesg("registering wakeup listeners")
      lID = k.evt.register("key_down", function()
        k.hooks.wakeup()
      end)
      lID2 = k.evt.register("touch", function()
        k.hooks.wakeup()
      end)
      kio.dmesg("suspending all processes")
      for pid, proc in pairs(procs) do
        if proc.stopped then
          prev_stopped[pid] = true
        else
          proc:handle(process.signals.SIGSTOP)
        end
      end
      kio.dmesg("turning off screens")
      for addr in component.list("screen", true) do
        component.invoke(addr, "turnOff")
      end
    end)

    k.hooks.add("wakeup", function()
      k.evt.unregister(lID)
      k.evt.unregister(lID2)
      for addr in component.list("screen", true) do
        component.invoke(addr, "turnOn")
      end
      for pid, proc in pairs(procs) do
        if not prev_stopped[pid] then
          proc:handle(process.signals.SIGCONT)
        end
      end
    end)
  end

  k.hooks.add("sandbox", function()
    -- userspace process api
    local signals = process.signals
    local process = {}
    k.sb.process = process
    k.sb.process.signals = signals
    function k.sb.process.spawn(a,b,c)
      return k.sched.spawn(a,b,c).pid
    end
    
    -- userspace may want a list of all PIDs
    function k.sb.process.list()
      local ret = {}
      for pid, proc in pairs(procs) do
        ret[#ret + 1] = pid
      end
      return ret
    end

    -- we can safely return only a very limited subset of process info
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
      if not pid then -- we can give a process more info about itself
        ret.env = info.env
        ret.io = info.io
      end
      return ret
    end

    function k.sb.process.current()
      return current
    end

    function k.sb.process.signal(pid, sig)
      return k.sched.signal(pid, sig)
    end

    function k.sb.process.thread(func, name)
      return k.sched.newthread(func, name)
    end

    function k.sb.process.sethandler(sig, func)
      checkArg(1, sig, "number")
      checkArg(2, func, "function")
      k.sched.getinfo().sighandlers[sig] = func
      return true
    end

    -- some of the userspace `os' api, specifically the process-centric stuff
    function k.sb.os.getenv(k)
      checkArg(1, k, "string", "number")
      return process.info().env[k]
    end

    function k.sb.os.setenv(k, v)
      checkArg(1, k, "string", "number")
      checkArg(2, v, "string", "number", "nil")
      process.info().env[k] = v
      return true
    end

    function k.sb.os.exit()
      process.signal(process.current(), process.signals.SIGKILL)
      coroutine.yield()
    end

    function k.sb.os.sleep(n)
      checkArg(1, n, "number")
      local max = computer.uptime() + n
      repeat
        coroutine.yield(max - computer.uptime())
      until computer.uptime() >= max
      return true
    end
  end)
end
