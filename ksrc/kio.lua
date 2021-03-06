-- kernel i/o

local kio = {}

kargs.loglevel = tonumber(kargs.loglevel) or 0

-- kio.errors: table
--   A table of common error messages.
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

-- kio.loglevels: table
--   Supported loglevels. Currently DEBUG, INFO, WARNING, ERROR, and PANIC.
kio.loglevels = {
  DEBUG   = 0,
  INFO    = 1,
  WARNING = 2,
  ERROR   = 3,
  PANIC   = 4
}

kio.levels = {
  [0] = "DEBUG",
  "INFO",
  "WARNING",
  "ERROR",
  "PANIC"
}

-- _pipe: table
--   Pipe template. Methods:
local _pipe = {}
-- _pipe:read([n:string or number]): string or nil or nil, string
--   If `n` is `"l"`, read a line. If `n` is `"a"`, read all available bytes. If `n` is a number, read `n` bytes.
function _pipe:read(n)
  checkArg(1, n, "number", "string", "nil")
  if type(n) == "string" then n = n:gsub("%*", "") end
  if self.closed and #self.buf == 0 then return nil end
  if n == "l" then
    while (not self.buf:find("\n")) and self.strict do
      if self.closed then return self.buf end
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
    if self.closed then return self.buf end
    coroutine.yield()
  end
  n = math.min(n, #self.buf)
  local ret = self.buf:sub(1, n)
  self.buf = self.buf:sub(n + 1)
  return ret
end

-- _pipe:write(data:string): boolean or nil, string
--   Write `data` to the pipe stream.
function _pipe:write(...)
  local args = table.pack(...)
  for i=1, args.n, 1 do
    args[i] = tostring(args[i])
  end
  local write = table.concat(args)
  if self.closed then
    return kio.error("BROKEN_PIPE")
  end
  self.buf = self.buf .. write
  return true
end

-- _pipe:size(): number
--   Return the current size of the pipe stream buffer.
function _pipe:size()
  return #self.buf
end

-- _pipe:close()
--   Close the pipe.
function _pipe:close()
  self.closed = true
end

-- _pipe:lines(fmt:string): function
--   Iterate over all lines in the pipe data.
function _pipe:lines(fmt)
  return function()
    return self:read(fmt or "l")
  end
end

-- kio.pipe(): table
--   Create a pipe.
function kio.pipe()
  return setmetatable({buf = "", strict = true}, {__index = _pipe}), "rw"
end

kio.__dmesg = {}

local console
do
  -- calling console() writes a line. that's it.
  local ac = kargs.console or ""
  local gpu, screen = ac:match("(.+),(.+)")
  gpu = (gpu and component.type(gpu) == "gpu" and gpu) or component.list("gpu")()
  screen = (screen and component.type(screen) == "screen" and screen) or component.list("screen")()
  gpu = component.proxy(gpu)
  gpu.bind(screen)
  local y = 0
  local w, h = assert(gpu.maxResolution())
  gpu.setResolution(w, h)
  gpu.fill(1, 1, w, h, " ")
  gpu.setForeground(0xaaaaaa)
  gpu.setBackground(0x000000)
  local _console = function(msg)
    if y == h then
      gpu.copy(1, 1, w, h, 0, -1)
      gpu.fill(1, h, w, 1, " ")
    else
      y = y + 1
    end
    gpu.set(1, y, msg)
  end

  function kio.__dmesg:write(msg)
  end

  kio.gpu = gpu
  kio.console = function(...)
    kio.__console(...)
    return kio.__dmesg:write(...)
  end
  kio.__console = _console
end

-- kio.error(err:string): nil, string
--   Return an error based on one of the errors in `kio.errors`.
function kio.error(err)
  return nil, kio.errors[err] or "generic error"
end

-- kio.dmesg(level:number, msg:string): boolean
--   Log `msg` to the console with loglevel `level`.
function kio.dmesg(level, msg)
  if not msg then msg = level level = nil end
  level = level or kio.loglevels.INFO
  for line in msg:gmatch("[^\n]+") do
    local mesg = string.format("[%5.05f] [%s] %s", computer.uptime(), kio.levels[level], line)
    if level >= kargs.loglevel then
      kio.console(mesg)
    else
      kio.__dmesg:write(mesg)
    end
--    table.insert(dmesg, mesg)
  end
  return true
end

function kio.redir(f)
  checkArg(1, f, "function")
  kio.console = f
end

do
  local panic = computer.pullSignal
  -- kio.panic(msg:string)
  --   Send the system into a panic state. After this function is called, the system MUST be restarted to resume normal operation.
  function kio.panic(msg)
    local traceback = msg
    local i = 1
    while true do
      local info = debug.getinfo(i)
      if not info then break end
      traceback = traceback .. string.format("\n  %s:%s: in %s'%s':", info.source:gsub("=*",""), info.currentline or "C", (info.namewhat ~= "" and info.namewhat .. " ") or "", info.name or "?")
      i = i + 1
    end
    traceback = traceback:gsub("\t", "  ")
    for line in traceback:gmatch("[^\n]+") do
      kio.dmesg(kio.loglevels.PANIC, line)
    end
    kio.dmesg(kio.loglevels.PANIC, "Kernel panic!")
    computer.beep(440, 1)
    while true do
      panic()
    end
  end
end

kio.dmesg(kio.loglevels.INFO, string.format("Starting %s version %s - built %s by %s", _KINFO.name, _KINFO.version, _KINFO.built, _KINFO.builder))

--#include "ksrc/buffer.lua"

