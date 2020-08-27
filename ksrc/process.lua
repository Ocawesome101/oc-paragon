-- scheduler part 1: process template

kio.dmesg(kio.loglevels.INFO, "ksrc/process.lua")

local process = {}

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

function process.new(args)
  checkArg(1, args, "table")
  local new = {
    pid = 1,                            -- process ID
    name = "unknown",                   -- process name
    env = {},                           -- environment variables
    threads = {},                       -- worker threads
    started = computer.uptime(),        -- time the process was started
    runtime = 0,                        -- time the process has spent running
    deadline = 0,                       -- signal wait deadline
    owner = security.users.user(),      -- process owner
    tty = false,                        -- false if not associated with a tty,
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

  for k,v in pairs(args) do new[k] = v end
  return setmetatable(new, {__index = process})
end

function process:resume(...)
  for i=1, #self.threads, 1 do
    kio.dmesg(kio.loglevels.DEBUG, "process " .. self.pid .. ": resuming thread " .. i)
    local thd = self.threads[i]
    local ok, ec = coroutine.resume(thd.coro, ...)
    if (not ok) or coroutine.status(thd.coro) == "dead" then
      kio.signal(kio.loglevels.DEBUG, "process " .. self.pid .. ": thread died: " .. i)
      self.threads[i] = nil
      computer.pushSignal("thread_died", self.pid, (type(ec) == "string" and 1 or ec), type(ec) == "string" and ec)
    end
    -- TODO: this may result in incorrect yield timeouts with multiple threads
    local nd = ec + computer.uptime()
    if nd < self.deadline then
      self.deadline = nd
    end
  end
  return true
end

function process:addThread(func, name)
  checkArg(1, func, "function")
  checkArg(2, name, "string", "nil")
  name = name or "thread" .. #self.threads + 1
  self.threads[#self.threads + 1] = {
    name = name,
    coro = coroutine.create(func)
  }
  return true
end

-- XXX this function is very dangerous. it SHOULD NOT, and I repeat, SHOULD NOT
-- XXX find its way into user code. EVER.
function process:info()
  return {
    env = self.env,
    started = self.started,
    runtime = self.runtime,
    deadline = self.deadline,
    io = self.io,
    sighandlers = self.sighandlers,
    threads = self.threads
  }
end

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

process.kill = process.handle

function process:stdin(file)
  checkArg(1, file, "table", "nil")
  if file and file.read and file.write and file.close then
    pcall(self.io.stdin.close, self.io.stdin)
    self.io.stdin = file
  end
  return self.io.stdin
end

function process:stdout(file)
  checkArg(1, file, "table", "nil")
  if file and file.read and file.write and file.close then
    pcall(self.io.stdout.close, self.io.stdout)
    self.io.stdout = file
  end
  return self.io.stdout
end

function process:stderr(file)
  checkArg(1, file, "table", "nil")
  if file and file.read and file.write and file.close then
    pcall(self.io.stderr.close, self.io.stderr)
    self.io.stderr = file
  end
  return self.io.stderr
end
