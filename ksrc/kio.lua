-- kernel i/o

kio = {}

kargs.loglevel = tonumber(kargs.loglevel) or 1

kio.errors = {
  FILE_NOT_FOUND = "no such file or directory",
  FILE_DIRECTORY = "file is a directory",
  IO_ERROR = "input/output error",
  UNSUPPORTED_OPERATION = "unsupported operation",
  PERMISSION_DENIED = "permission denied",
  DEV_FULL = "device is full",
  DEV_RO = "device is read only",
  BROKEN_PIPE = "broken pipe"
}

kio.loglevels = {
  DEBUG   = 0,
  INFO    = 1,
  WARNING = 2,
  ERROR   = 3,
  PANIC   = 4.
}

kio.levels = {
  [0] = "DEBUG",
  "INFO",
  "WARNING",
  "ERROR",
  "PANIC"
}

-- template stream
local _stream = {}
function _stream:pipe(n)
  checkArg(1, n, "number", "string", "nil")
  if type(n) == "string" then n = n:gsub("%*", "") end
  if self.closed and #self.buf == 0 then return nil end
  if n == "l" then
    while not self.buf:find("\n") and self.strict do
      coroutine.yield()
    end
    local s = self.buf:find("\n") or #self.buf
    local ret = self.buf:sub(1, s)
    self.buf = self.buf:sub(s + 1)
    return ret
  elseif n == "a" then
    local ret = self.buf
    self.buf = ""
    return ret
  end
  while #self.buf < n and self.strict do
    coroutine.yield()
  end
  n = math.min(n, #self.buf)
  local ret = self.buf:sub(1, n)
  self.buf = self.buf:sub(n + 1)
  return ret
end

function _pipe:write(data)
  if self.closed then
    return kio.error("BROKEN_PIPE")
  end
  self.buf = self.buf .. data
end

function _pipe:size()
  return #self.buf
end

function _pipe:close()
  self.closed = true
end

function kio.pipe()
  return setmetatable({buf = ""}, {__index = _pipe})
end

-- temporary log buffer until we get a root filesystem
local dmesg = {}

do
  -- calling console() writes a line. that's it.
  local ac = kargs.console or ""
  local gpu, screen = ac:match("(.+),(.+)")
  gpu = (gpu and component.type(gpu) == "gpu" and gpu) or component.list("gpu")()
  screen = (screen and component.type(screen) == "screen" and screen) or component.list("screen")()
  gpu = component.proxy(gpu)
  local y = 0
  local w, h = gpu.maxResolution()
  gpu.setResolution(w, h)
  function console(msg)
    if y == h then
      gpu.copy(1, 1, w, h, 0, -1)
      gpu.fill(1, h, w, 1, " ")
    else
      y = y + 1
    end
    gpu.set(1, y, msg)
  end

  kio.console = console
end

function kio.error(err)
  return nil, kio.errors[err] or "generic error"
end

function kio.dmesg(level, msg)
  local mesg = string.format("[%.2f] [%s] %s", computer.uptime(), kio.levels[level], msg)
  if level > kio.loglevel then
    kio.console(mesg)
  end
  table.insert(dmesg, mesg)
  return true
end

do
  local panic = computer.pullSignal
  function kio.panic(msg)
    local traceback = msg
    local i = 1
    while true do
      local info = debug.getinfo(i)
      if not info then break end
      traceback = traceback .. string.format("\n  %s:%s: in %s'%s':", info.source:sub(2), info.currentline or "C", (info.namewhat ~= "" and info.namewhat .. " ") or "", info.name or "?")
      i = i + 1
    end
    for line in traceback:gmatch("[^\n]+") do
      kio.dmesg(kio.loglevels.PANIC, line)
    end
    kio.dmesg(kio.loglevels.PANIC, "Kernel panic!")
    computer.beep(1)
    while true do
      panic()
    end
  end
end
