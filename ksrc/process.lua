-- scheduler part 1: process template

kio.dmesg(kio.loglevels.INFO, "ksrc/process.lua")

local process = {}

do
  -- process.signals: table
  --   A table of signals. Currently available: SIGHUP, SIGINT, SIGKILL, SIGTERM, SIGCONT, SIGSTOP. The table is reverse-indexed so that `process.signals[process.signals.SIGHUP] = "SIGHUP"`.
  local signals = {
    SIGHUP  = 1,
    SIGINT  = 2,
    SIGKILL = 9,
    SIGTERM = 15,
    SIGCONT = 18,
    SIGSTOP = 19,
    [1]     = "SIGHUP",
    [2]     = "SIGINT",
    [9]     = "SIGKILL",
    [15]    = "SIGTERM",
    [18]    = "SIGCONT",
    [19]    = "SIGSTOP"
  }
  process.signals = signals
  
  local function default(self, sig)
    self.dead = true
  end

  local function try_get(tab, field)
    if tab[field] then
      local ret = tab[field]
      tab[field] = nil
      return ret
    end
    return {}
  end

  -- process.new(args:table): table
  --   Create a new process. `args` is used for internal undocumented purposes.
  function process.new(args)
    checkArg(1, args, "table")
    local new = {
      pid = 1,                            -- process ID
      name = "unknown",                   -- process name
      env = {},                           -- environment variables
      threads = {},                       -- threads
      started = computer.uptime(),        -- time the process was started
      runtime = 0,                        -- time the process has spent running
      deadline = 0,                       -- signal wait deadline
      owner = k.security.users.user(),    -- process owner
      tty = args.stdin and args.stdin.tty
      or false,                           -- false if not associated with a tty,
                                          -- else a string in the format "ttyN"
                                          -- where N is the tty id
      msgs = {},                          -- internal thread message queue
      sighandlers = {},                   -- signal handlers
      handles = {},                       -- all open handles
      priority = math.huge,               -- lower values are resumed first
      io = {
        stdin = try_get(args, "stdin"),   -- standard input
        stdout = try_get(args, "stdout"), -- standard output
        stderr = try_get(args, "stderr")  -- standard error
      }
    }

    new.io.input = new.io.stdin
    new.io.output = new.io.stdout
    new.env.USER = new.env.USER or "root"
    new.env.UID = new.env.UID or 0
  
    for k,v in pairs(args) do new[k] = v end
    return setmetatable(new, {__index = process})
  end
  
  -- process:resume(...): boolean
  --   Resume all threads in the process.
  function process:resume(...)
    local resumed = computer.uptime()
    for i=1, #self.threads, 1 do
      local thd = self.threads[i]
      local ok, ec = coroutine.resume(thd.coro, ...)
      if (not ok) or coroutine.status(thd.coro) == "dead" then
        kio.dmesg(kio.loglevels.DEBUG, "process " .. self.pid .. ": thread died: " .. i)
        self.threads[i] = nil
        if ec then kio.dmesg(tostring(ec)) end
        if self.pid == 1 then -- we are init, PANIC!!!
          kio.panic(tostring(ec))
        end
        computer.pushSignal("thread_died", self.pid, (type(ec) == "string" and 1 or ec), type(ec) == "string" and ec)
      end
      -- TODO: this may result in incorrect yield timeouts with multiple threads
      if type(ec) == "number" then
        local nd = ec + computer.uptime()
        if nd < self.deadline then
          self.deadline = nd
        end
      else
        if ec then kio.dmesg(kio.loglevels.DEBUG, tostring(ec)) end
        self.deadline = math.huge
      end
    end
    if #self.threads == 0 then
      self.dead = true
    end
    self.runtime = self.runtime + (computer.uptime() - resumed)
    return true
  end

  -- process:addThread(func:function[, name:string])
  --   Add a thread to the process.
  function process:addThread(func, name)
    checkArg(1, func, "function")
    checkArg(2, name, "string", "nil")
    name = name or "thread" .. #self.threads + 1
    self.threads[#self.threads + 1] = {
      name = name,
      coro = coroutine.create(function()return assert(xpcall(func, debug.traceback)) end)
    }
    return true
  end
  
  -- XXX this function is very dangerous. it SHOULD NOT, and I repeat, SHOULD NOT
  -- XXX find its way into user code. EVER.
  -- process:info(): table
  --   See `k.sched.getinfo`.
  function process:info()
    return {
      io = self.io,
      pid = self.pid,
      env = self.env,
      name = self.name,
      owner = self.owner,
      started = self.started,
      runtime = self.runtime,
      threads = self.threads,
      deadline = self.deadline,
      sighandlers = self.sighandlers,
      stdin = process.stdin, -- convenience
      stdout = process.stdout,
      stderr = process.stderr,
      input = process.input,
      output = process.output
    }
  end

  -- process:handle(sig:number): boolean or nil, string
  --   Handles signal `sig` according to an internal signal handler. Unless the process's PID is 1, SIGKILL will always kill the process.
  function process:handle(sig)
    if sig == signals.SIGKILL and self.pid ~= 1 then -- init can override SIGKILL behavior
      self.dead = true
      return true
    end
    if sig == signals.SIGSTOP or sig == signals.SIGCONT then -- these are non-blockable
      self.stopped = sig == signals.SIGSTOP
      return true
    end
    local handler = self.sighandlers[sig] or default
    local result = table.pack(pcall(handler, self, sig))
    if not result[1] then
      return nil, result[2]
    end
    return table.unpack(result, 2)
  end

  -- process:kill()
  --   See `process:handle`.
  process.kill = process.handle

  -- process:input([file:table]): table
  --   If `file` is provided and is valid, set the process's io.input to `file`. Always returns the current standard input.
  function process:input(file)
    checkArg(1, file, "table", "nil")
    if file and file.read and file.write and file.close then
      if not self.io.input.tty then pcall(self.io.input.close, self.io.input) end
      self.io.input = file
    end
    return self.io.input
  end

  -- process:output([file:table]): table
  --   Like `process:stdin()`, but operates on the output.
  function process:output(file)
    checkArg(1, file, "table", "nil")
    if file and file.read and file.write and file.close then
      if not self.io.output.tty then pcall(self.io.output.close, self.io.output) end
      self.io.output = file
    end
    return self.io.output
  end

  -- process:stderr([file:table]): table
  --   Like `process:stdin()`, but operates on the standard error.
  function process:stderr(file)
    checkArg(1, file, "table", "nil")
    if file and file.read and file.write and file.close then
      if not io.stderr.tty then pcall(self.io.stderr.close, self.io.stderr) end
      self.io.stderr = file
    end
    return self.io.stderr
  end

  function process:stdin()
    return self.io.stdin
  end

  function process:stdout()
    return self.io.stdout
  end
end
