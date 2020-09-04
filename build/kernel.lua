--[[
        Paragon kernel.
        Copyright (C) 2020 Ocawesome101
        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU General Public License as published by
        the Free Software Foundation, either version 3 of the License, or
        (at your option) any later version.
        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU General Public License for more details.
        You should have received a copy of the GNU General Public License
        along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]

-- parse kernel arguments

local cmdline = table.concat(table.pack(...), " ") -- ex. "init=/bin/sh loglevel=3 quiet"
kargs = {}

for word in cmdline:gmatch("[^%s]+") do
  local k, v = word:match("(.-)=(.+)")
  k, v = k or word, v or true
  kargs[k] = v
end

_G._KINFO = {
  name    = "Paragon",
  version = "0.0.1",
  built   = "2020/09/03",
  builder = "ocawesome101@archlinux"
}

-- kernel i/o

kio = {}

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

-- _pipe:write(data:string): boolean or nil, string
--   Write `data` to the pipe stream.
function _pipe:write(data)
  if self.closed then
    return kio.error("BROKEN_PIPE")
  end
  self.buf = self.buf .. data
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

-- kio.pipe(): table
--   Create a pipe.
function kio.pipe()
  return setmetatable({buf = ""}, {__index = _pipe})
end

-- temporary log buffer until we get a root filesystem
local dmesg = {}

local console
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
  gpu.fill(1, 1, w, h, " ")
  gpu.setForeground(0xaaaaaa)
  gpu.setBackground(0x000000)
  console = function(msg)
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

-- kio.error(err:string): nil, string
--   Return an error based on one of the errors in `kio.errors`.
function kio.error(err)
  return nil, kio.errors[err] or "generic error"
end

-- kio.dmesg(level:number, msg:string): boolean
--   Log `msg` to the console with loglevel `level`.
function kio.dmesg(level, msg)
  level = level or kio.loglevels.INFO
  local mesg = string.format("[%5.05f] [%s] %s", computer.uptime(), kio.levels[level], msg)
  if level >= kargs.loglevel then
    kio.console(mesg)
  end
  table.insert(dmesg, mesg)
  return true
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

-- kernel drivers

kio.dmesg(kio.loglevels.INFO, "ksrc/kdrv.lua")

kdrv = {}

kdrv.fs = {}
kdrv.tty = {}
kdrv.net = {}

-- BROFS filesystem driver

do
  local drv = {}

  drv.name = "BROFS driver"
  drv.authors = {"Ocawesome101"}
  drv.license = {"GPLv3"}

  local temp = {}

  local function readSectors(d, s, e)
    local r = ""
    for i=s, e, 1 do
      r = r .. (d.readSector(i) or "")
    end
    return r
  end

  local function strip(t)
    return t:gsub("/+", "")
  end

  function temp:spaceUsed()
    return math.huge
  end

  function temp:spaceTotal()
    return self.dev.getCapacity()
  end

  function temp:isReadOnly()
    return true
  end

  local hn = 0
  function temp:open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string", "nil")
    file = strip(file)
    kio.dmesg(kio.loglevels.DEBUG, "tryopen "..file)
    if self.ftable[file] then
      local new = {
        ptr = 0,
        file = self.ftable[file]
      }
      local n = hn + 1
      hn = n
      self.handles[n] = new
      kio.dmesg(kio.loglevels.DEBUG, "opened as " ..n)
      return n
    else
      return kio.error("FILE_NOT_FOUND")
    end
  end

  function temp:read(h, n)
    checkArg(1, h, "number")
    checkArg(2, n, "number")
    if not self.handles[h] then
      return nil, "bad file descriptor"
    end
    h = self.handles[h]
    if h.ptr >= h.file.size then
      return nil
    end
    if h.ptr + n >= h.file.size then
      n = h.file.size - h.ptr
    end
    local s, e = h.file.start + (h.ptr // 512), h.file.start + (h.ptr // 512) + (n // 512)
    local approx = readSectors(self.dev, s, e)
    local t = (h.ptr - ((h.ptr // 512) * 512))
    h.ptr = h.ptr + n
    local data = approx:sub(t, t + n)
    return data
  end

  function temp:seek(h, whence, offset)
    checkArg(1, h, "number")
    checkArg(2, whence, "string", "nil")
    checkArg(3, offset, "number", "nil")
    if not self.handles[h] then
      return nil, "bad file descriptor"
    end
    h = self.handles[h]
    whence, offset = whence or "cur", offset or 0
    whence = (whence == "cur" and h.ptr) or (whence == "set" and 0) or (whence == "end" and h.file.size)
    if type(whence) == "string" then
      return nil, "invalid 'whence' argument (expected 'cur', 'set', or 'end')"
    end
    h.ptr = math.max(0, math.min(h.file.size, whence + offset))
    return h.ptr
  end

  function temp:write(h, data)
    return kio.error("DEV_RO")
  end

  function temp:close(h)
    checkArg(1, h, "number")
    self.handles[h] = nil
  end

  function temp:makeDirectory()
    return kio.error("DEV_RO")
  end

  function temp:rename()
    return kio.error("DEV_RO")
  end

  function temp:exists(file)
    checkArg(1, file, "string")
    file = strip(file)
    kio.dmesg(kio.loglevels.DEBUG, "exists", file)
    if self.ftable[file] then
      return true
    end
    return false
  end

  function temp:isDirectory()
    return false -- directories are unsupported
  end

  function temp:lastModified()
    return 0
  end

  function temp:stat()
    return {
      permissions = 292, -- 100100100, r--r--r--
      -- TODO: possibly more fields?
    }
  end

  function temp:list()
    local files = {}
    for k, v in pairs(self.ftable) do
      table.insert(files, k)
    end
    return files
  end

  function temp:size(file)
    checkArg(1, file, "string")
    file = strip(file)
    if not self.ftable(file) then
      return kio.error("FILE_NOT_FOUND")
    end
    return self.ftable[file].size
  end

  function temp:remove()
    return kio.error("DEV_RO")
  end

  function temp:setLabel(label)
    checkArg(1, label, "string")
    if self.dev.setLabel then
      return self.dev.setLabel(label)
    else
      self.label = label
    end
  end

  function temp:getLabel()
    if self.dev.getLabel then
      return self.dev.getLabel()
    else
      return self.label
    end
  end

  function drv.create(prx, label) -- takes an unmanaged drive (or a partition / file wrapper) and returns a BROFS interface
    kio.dmesg(kio.loglevels.DEBUG, "reading BROFS file table")
    local ftbl = ""
    ftbl = readSectors(prx, 1, 2)
    local ftable = {}
    local inpack = "<I2I2I2I1I1c24"
    for i=1, 32, 1 do
      local n = (i - 1) * 32 + 1
      if n == 0 then n = 1 end
      kio.dmesg(kio.loglevels.DEBUG, n.." "..n+31)
      local seg = ftbl:sub(n, n + 31)
      local start, size, prealloc, flags, _, fname = string.unpack(inpack, seg)
      kio.dmesg(kio.loglevels.DEBUG, "BROFS: "..table.concat({start,size,fname}," "))
      if flags == 0 then
        kio.dmesg(kio.loglevels.DEBUG, "BROFS: file flags < 1")
        break
      end
      -- rid us of trailing \0s in the filename
      fname = fname:gsub("\0", "")
      -- file size is stored in approximate sectors but we need the exact count
      local last = prx.readSector(start + size - 1)
      last = last:gsub("\0", "")
      local xsize = (size - 1) * 512 + #last
      local ent = {
        start = start,
        size = xsize,
        sect = size
        -- NOTE: prealloc is not used as the generated interface is read-only
      }
      ftable[fname] = ent
    end
    return setmetatable({dev = prx, ftable = ftable, handles = {}, label = label or (prx.getLabel and prx.getLabel()) or "BROFS"}, {__index = temp})
  end

  kdrv.fs.brofs = drv
end

-- managed filesystem "driver"

do
  local drv = {}
  drv.name = "managed filesystem driver"
  drv.authors = {"Ocawesome101"}
  drv.license = {"GPLv3"}

  local default = {}
  setmetatable(default, {
    __index = function(_, k)
      default[k] = function(self, ...)
        if self.dev[k] then
          return self.dev[k](...)
        else
          error((string.format("attempt to call field '%s' (a nil value)", k)))
        end
      end
      return default[k]
    end
  })
  
  function default:stat(file)
    return {
      permissions = self:isReadOnly() and 292 or 438
    }
  end
  
  function drv.create(prx)
    checkArg(1, prx, "table", "string")
    if type(prx) == "string" then prx = component.proxy(prx) end
    return setmetatable({dev = prx}, {__index = default})
  end

  kdrv.fs.managed = drv
end



-- vfs

kio.dmesg(kio.loglevels.INFO, "ksrc/vfs.lua")

-- TODO: mount system is currently pretty basic.
local vfs = {}
do
  local mnt = {}

  --[[ expected procedure:
     1. use vfs.resolve to resolve a filepath to a proxy and a path on the proxy
     2. operate on the proxy
     the vfs api does not provide all available filesystem functions; see
     'misc/fsapi.lua' for an api that does.
     note that while running a kernel without the fsapi module, you'll need to
     either assign it as an initrd module or set 'security.uspace_vfs=1' in the
     kernel command line to allow userspace to access the vfs api (not
     recommended!). ]]

  local function segments(path)
    local segs = {}
    for s in path:gmatch("[^/]+") do
      if s == ".." then
        if #segs > 0 then
          table.remove(segs, #segs)
        end
      else
        table.insert(segs, s)
      end
    end
    return segs
  end

  -- XXX: vfs.resolve does NOT check if a file exists.
  -- vfs.resolve(path:string): table, string or nil, string
  --   Tries to resolve a file path to a filesystem proxy.
  function vfs.resolve(path)
    checkArg(1, path, "string")
    kio.dmesg(kio.loglevels.DEBUG, "vfs: resolve "..path)
    if path == "/" then
      if mnt["/"] then
        return mnt["/"], ""
      else
        return nil, "root filesystem not mounted"
      end
    end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    local segs = segments(path)
    for i=#segs, 1, -1 do
      local retpath = "/" .. table.concat(segs, "/", i, #segs)
      local try = "/" .. table.concat(segs, "/", 1, i)
      if mnt[try] then
        return mnt[try], retpath
      end
    end
    if path:sub(1,1)=="/" then
      return vfs.resolve("/"), path
    end
    kio.dmesg(kio.loglevels.DEBUG, "no such file: ".. path)
    return kio.error("FILE_NOT_FOUND")
  end

  -- vfs.mount(prx:table, path:string): boolean or nil, string
  --   Tries to mount the provided proxy at the provided file path.
  function vfs.mount(prx, path)
    checkArg(1, prx, "table")
    checkArg(2, path, "string")
    path = "/" .. table.concat(segments(path), "/")
    if mnt[path] then
      return nil, "there is already a filesystem mounted there"
    end
    mnt[path] = prx
    return true
  end
  
  -- vfs.mounts(): table
  --   Return a table with keys addresses and values paths of all mounted filesystems.
  function vfs.mounts()
    local ret = {}
    for k, v in pairs(mnt) do
      ret[v.address] = k
    end
    return ret
  end

  -- vfs.umount(path:string): boolean or nil, string
  --   Tries to unmount the proxy at the provided path.
  function vfs.umount(path)
    checkArg(1, path, "string")
    path = "/" .. table.concat(segments(path), "/")
    if not mnt[path] then
      return nil, "no such device"
    end
    mnt[path] = nil
    return true
  end

  -- vfs.stat(file:string): table or nil, string
  --   Tries to get information about a file or directory.
  function vfs.stat(file)
    checkArg(1, file, "string")
    local node, path = vfs.resolve(file)
    if not node then
      return nil, path
    end
    return node:stat(path)
  end
end

-- utils

do
  function table.copy(tbl)
    local seen = {}
    local function copy(t)
      local ret = {}
      for k, v in pairs(t) do
        if type(v) == "table" then
          if not seen[v] then
            seen[v] = true
            ret[k] = copy(v)
          end
        else
          ret[k] = v
        end
      end
      return ret
    end
    return copy(tbl)
  end
end

-- kernel api

kio.dmesg(kio.loglevels.INFO, "ksrc/kapi.lua")
k = {}
k.args    = kargs
k.io      = kio
k.info    = _KINFO
k.process = sched
k.drv     = kdrv

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
  
  -- process:resume(...): boolean
  --   Resume all threads in the process.
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

  -- process:addThread(func:function[, name:string])
  --   Add a thread to the process.
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
  -- process:info(): table
  --   See `k.sched.getinfo`.
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

  -- process:stdin([file:table]): table
  --   If `file` is provided and is valid, set the process's standard input to `file`. Always returns the current standard input.
  function process:stdin(file)
    checkArg(1, file, "table", "nil")
    if file and file.read and file.write and file.close then
      pcall(self.io.stdin.close, self.io.stdin)
      self.io.stdin = file
    end
    return self.io.stdin
  end

  -- process:stdout([file:table]): table
  --   Like `process:stdin()`, but operates on the standard output.
  function process:stdout(file)
    checkArg(1, file, "table", "nil")
    if file and file.read and file.write and file.close then
      pcall(self.io.stdout.close, self.io.stdout)
      self.io.stdout = file
    end
    return self.io.stdout
  end

  -- process:stderr([file:table]): table
  --   Like `process:stdin()`, but operates on the standard error.
  function process:stderr(file)
    checkArg(1, file, "table", "nil")
    if file and file.read and file.write and file.close then
      pcall(self.io.stderr.close, self.io.stderr)
      self.io.stderr = file
    end
    return self.io.stderr
  end
end

-- a scheduler! --

kio.dmesg(kio.loglevels.INFO, "ksrc/scheduler.lua")

do
  local procs = {}
  local s = {}
  local last, current = 0, 0

  -- k.sched.spawn(func:function, name:string): table
  --   Spawns a process, adding `func` to its threads.
  function s.spawn(func, name)
    last = last + 1
    local p = procs[current]
    local new = process.new {
      pid = last,
      parent = current,
      env = p and table.copy(p.env) or {},
      stdin = p and p.io.stdin or {},
      stdout = p and p.io.stdout or {},
      stderr = p and p.io.stderr or {}
    }
    procs[new.pid] = new
    return new -- the userspace function will just return the PID
  end

  -- k.sched.getinfo(pid:number): table or nil, string
  --   Returns information about a process.
  function s.getinfo(pid)
  end

  k.sched = s
end

-- Paragon eXecutable parsing?

kio.dmesg(kio.loglevels.INFO, "ksrc/exec/px.lua")


-- basic event listeners

kio.dmesg(kio.loglevels.INFO, "ksrc/misc/event.lua")

do
  local event = {}
  local listeners = {}
  local ps = computer.pullSignal

  function computer.pullSignal(timeout)
    checkArg(1, timeout, "number", "nil")

    local sig = table.pack(ps(timeout))
    if sig.n > 0 then
      for k, v in pairs(listeners) do
        if v.signal == sig[1] then
          local ok, ret = pcall(v.callback, table.unpack(sig))
          if not ok and ret then
            kio.dmesg(kio.loglevels.WARNING, "event handler error: " .. ret)
          end
        end
      end
    end

    return table.unpack(sig)
  end

  function event.register(sig, func)
    checkArg(1, sig, "string")
    checkArg(2, func, "function")
    local n = 1
    while listeners[n] do
      n = n + 1
    end
    listeners[n] = {
      sig = sig,
      func = func
    }
    return n
  end

  function event.unregister(id)
    checkArg(1, id, "number")
    listeners[id] = nil
    return true
  end

  k.evt = event
end

-- bi32 module for Lua 5.3

kio.dmesg(kio.loglevels.INFO, "ksrc/misc/bit32_lua53.lua")

do
  if tonumber(_VERSION:match("5%.(.)")) > 2 then -- if we aren't on 5.3+ then don't do anything
    -- loaded from a string so this will still parse on Lua 5.3
    -- this is the OpenOS bit32 library
    load([[
_G.bit32 = {}

local function fold(init, op, ...)
  local result = init
  local args = table.pack(...)
  for i = 1, args.n do
    result = op(result, args[i])
  end
  return result
end

local function trim(n)
  return n & 0xFFFFFFFF
end

local function mask(w)
  return ~(0xFFFFFFFF << w)
end

function bit32.arshift(x, disp)
  return x // (2 ^ disp)
end

function bit32.band(...)
  return fold(0xFFFFFFFF, function(a, b) return a & b end, ...)
end

function bit32.bnot(x)
  return ~x
end

function bit32.bor(...)
  return fold(0, function(a, b) return a | b end, ...)
end

function bit32.btest(...)
  return bit32.band(...) ~= 0
end

function bit32.bxor(...)
  return fold(0, function(a, b) return a ~ b end, ...)
end

local function fieldargs(f, w)
  w = w or 1
  assert(f >= 0, "field cannot be negative")
  assert(w > 0, "width must be positive")
  assert(f + w <= 32, "trying to access non-existent bits")
  return f, w
end

function bit32.extract(n, field, width)
  local f, w = fieldargs(field, width)
  return (n >> f) & mask(w)
end

function bit32.replace(n, v, field, width)
  local f, w = fieldargs(field, width)
  local m = mask(w)
  return (n & ~(m << f)) | ((v & m) << f)
end

function bit32.lrotate(x, disp)
  if disp == 0 then
    return x
  elseif disp < 0 then
    return bit32.rrotate(x, -disp)
  else
    disp = disp & 31
    x = trim(x)
    return trim((x << disp) | (x >> (32 - disp)))
  end
end

function bit32.lshift(x, disp)
  return trim(x << disp)
end

function bit32.rrotate(x, disp)
  if disp == 0 then
    return x
  elseif disp < 0 then
    return bit32.lrotate(x, -disp)
  else
    disp = disp & 31
    x = trim(x)
    return trim((x >> disp) | (x << (32 - disp)))
  end
end

function bit32.rshift(x, disp)
  return trim(x >> disp)
end
    ]], "=(bit32)", "t", _G)()
  end
end

-- UUID module. UUID implementation copied from OpenOS

kio.dmesg(kio.loglevels.INFO, "ksrc/misc/uuid.lua")

do
  k.uuid = {}

  function k.uuid.next()
    local sets = {4, 2, 2, 2, 6}
    local result = ""
    local pos = 0

    for _, set in ipairs(sets) do
      if #result > 0 then
        result = result .. "-"
      end
      for i=1, set, 1 do
        local byte = math.random(0, 255)
        if pos == 6 then
          byte = bit32.bor(bit32.band(byte, 0x0F), 0x40)
        elseif pos == 8 then
          byte = bit32.bor(bit32.band(byte, 0x3F), 0x80)
        end
        result = string.format("%s%02x", result, byte)
        pos = pos + 1
      end
    end

    return result
  end
end

-- basic event listeners

kio.dmesg(kio.loglevels.INFO, "ksrc/misc/event.lua")

do
  local event = {}
  local listeners = {}
  local ps = computer.pullSignal

  function computer.pullSignal(timeout)
    checkArg(1, timeout, "number", "nil")

    local sig = table.pack(ps(timeout))
    if sig.n > 0 then
      for k, v in pairs(listeners) do
        if v.signal == sig[1] then
          local ok, ret = pcall(v.callback, table.unpack(sig))
          if not ok and ret then
            kio.dmesg(kio.loglevels.WARNING, "event handler error: " .. ret)
          end
        end
      end
    end

    return table.unpack(sig)
  end

  function event.register(sig, func)
    checkArg(1, sig, "string")
    checkArg(2, func, "function")
    local n = 1
    while listeners[n] do
      n = n + 1
    end
    listeners[n] = {
      sig = sig,
      func = func
    }
    return n
  end

  function event.unregister(id)
    checkArg(1, id, "number")
    listeners[id] = nil
    return true
  end

  k.evt = event
end


-- load and mount the initfs as /

kio.dmesg(kio.loglevels.INFO, "ksrc/iramfs.lua")

do
  local fs = kargs.boot or (computer.getBootAddress and computer.getBootAddress()) or kio.panic("neither boot=? nor computer.getBootAddress present")

  local pspec, addr, pn = fs:match("(.+)%((.+),(%d+)%)")
  addr = addr or fs:gsub("[^%w%-]+", "")
  if not component.type(addr) then
    kio.panic("invalid bootfs specification (got " .. addr .. ")")
  end
  if component.type(addr) == "drive" then -- unmanaged, read partition table as specified
    if not pspec then
      kio.dmesg(kio.loglevels.WARNING, "no partitioning scheme specified!")
      kio.dmesg(kio.loglevels.WARNING, "defaulting to full drive as filesystem!")
    end
    if pspec and not kdrv.fs[pspec] then
      kio.panic("missing driver for partitioning scheme " .. pspec .. "!")
    end
  elseif component.type(addr) == "filesystem" then -- managed
    if not kdrv.fs.managed then
      kio.panic("managed filesystem driver not present!")
    end
    kio.dmesg(kio.loglevels.DEBUG, "creating 'managed' proxy")
    local temp = component.proxy(addr)
    kio.dmesg(kio.loglevels.DEBUG, "creating fake 'drive'")
    local fake = {} -- fake drive component to pass to the BROFS driver so we
                    -- can mount the initfs at /
    -- TODO: initfs from a managed disk will be REALLY SLOW if we keep using
    -- TODO: this method, maybe cache sectors?
    -- TODO: or maybe it isn't a big deal and people will just load from drives
    -- TODO: like intended.
    function fake.readSector(s)
      local handle, err = temp.open("pinitfs.img", "r")
      if not handle then
        kio.dmesg(kio.loglevels.DEBUG, "fakedrv: "..err)
      end
      s = (s - 1) * 512
      local ok, err = temp.seek(handle, "set", s)
      if not ok then
        temp.close(handle)
        return nil, err
      end
      local data = temp.read(handle, 512)
      temp.close(handle)
      return data
    end
    function fake.getLabel()
      return "initfs"
    end
    kio.dmesg(kio.loglevels.DEBUG, "creating initfs proxy")
    local idisk = kdrv.fs.brofs.create(fake)
    kio.dmesg(kio.loglevels.INFO, "mounting initfs at /")
    vfs.mount(idisk, "/")
  else
    kio.panic("invalid bootfs specification:\n  component is not 'drive' or 'filesystem'")
  end
end

-- load modules in order from initfs/mod*.lua

kio.dmesg(kio.loglevels.INFO, "ksrc/mods.lua")

-- <basic> loadfile(file:string): function or nil, string
--   Tries to load `file` from the filesystem.
function loadfile(file)
  checkArg(1, file, "string")
  kio.dmesg(kio.loglevels.DEBUG, "loadfile: "..file)
  local node, path = vfs.resolve(file)
  if not node then
    kio.dmesg(kio.loglevels.DEBUG, "loadfile: "..path)
    return nil, path
  end
  local handle, err = node:open(path, "r")
  if not handle then
    kio.dmesg(kio.loglevels.DEBUG, "loadfile: node: "..err)
    return nil, err
  end
  local data = ""
  repeat
    local chunk, err = node:read(handle, math.huge)
    if not chunk and err then
      node:close(handle)
      kio.dmesg(kio.loglevels.DEBUG, "loadfile: "..err)
      return nil, err
    end
    data = data .. (chunk or "")
  until not chunk
  node:close(handle)
  return load(data, "=" .. file, "bt", _G)
end

do
  local rootfs, err = vfs.resolve("/")
  if not rootfs then
    kio.panic(err)
  end
  local files = rootfs:list("/")
  table.sort(files)
  kio.dmesg(kio.loglevels.DEBUG, "loading modules from initfs")
  for i=1, #files, 1 do
    kio.dmesg(kio.loglevels.DEBUG, files[i])
    if files[i]:sub(1,3) == "mod" and files[i]:sub(-4) == ".lua" then
      local ok, err = loadfile(files[i])
      if not ok then
        kio.dmesg(kio.loglevels.ERROR, files[i]..": "..err)
      else
        local ok, ret = pcall(ok)
        if not ok then
          kio.dmesg(kio.loglevels.ERROR, files[i]..": "..err)
        end
      end
    end
  end
end

-- load the fstab from the specified rootfs and mount filesystems accordingly
-- from here on we work with the real rootfs, not the initfs

kio.dmesg(kio.loglevels.INFO, "ksrc/fstab.lua")

-- mount the rootfs
do
  kargs.root = kargs.root or computer.getBootAddress and
                       string.format("managed(%s,1)", computer.getBootAddress())
  if not kargs.root and not computer.getBootAddress then
    kio.panic("rootfs not specified and no way to find it!")
  end

  local pspec, addr, n = kargs.root:match("(%w+)%(([%w%-]+),(%d+)%)")
  kio.dmesg(kio.loglevels.DEBUG, pspec.."("..addr..","..n..")")
  addr = addr or kargs.root
  if component.type(addr) == "filesystem" then
    pspec = "managed"
    if not k.drv.fs.managed then
      kio.panic("managed fs driver required but not present")
    end
    local prx, err = component.proxy(addr)
    local rfs = kdrv.fs.managed.create(prx)
    vfs.umount("/")
    vfs.mount(rfs, "/")
  elseif component.type(addr) == "drive" then
    --[[ TODO TODO TODO TODO TODO
         SUPPORT UNMANAGED DRIVES!
         TODO TODO TODO TODO TODO ]]
    kio.panic("TODO - unmanaged drive support!")
    pspec = pspec or "unmanaged" -- defaults to full drive as filesystem
  else
    kio.panic("invalid rootfs partspec: "..kargs.root)
  end
end

-- load and parse the fstab
do
  local ifs, p = vfs.resolve("/etc/fstab")
  if not ifs then
    kio.panic(p)
  end
  local handle, err = ifs:open(p)
  if not handle then
    kio.dmesg(kio.loglevels.WARNING, "error opening /etc/fstab: "..err)
    goto eol
  end
  local data = ""
  repeat
    local chunk = ifs:read(handle, math.huge)
    data = data .. (chunk or "")
  until not chunk
  ifs:close(handle)
  for line in data:gmatch("[^\n]+") do
    -- e.g. to specify the third partition on the OCGPT of a drive:
    -- ocgpt(42d7,3)   /   openfs   rw
    -- managed(5732,1)   /   managed   rw
    local pspec, fsspec, path, mode = line:match("(.-)%s+(.-)%s+(.-)%s+(.-)")
    local ptab, addr, a
  end
  ::eol::
end

-- TTY driver --

kio.dmesg(kio.loglevels.INFO, "ksrc/tty.lua")

do
  local vt = {}
  -- these are the default VGA colors
  local colors = {
    0x000000,
    0xaa0000,
    0x00aa00,
    0x0000aa,
    0xaaaa00,
    0xaa00aa,
    0x00aaaa,
    0xaaaaaa
  }
  local bright = {
    0x555555,
    0xff5555,
    0x55ff55,
    0x5555ff,
    0xffff55,
    0xff55ff,
    0x55ffff,
    0xffffff
  }
  -- and these are the 240 \27[38;5;NNNm colors
  local palette = {
    0x000000,
    0xaa0000,
    0x00aa00,
    0x0000aa,
    0xaaaa00,
    0xaa00aa,
    0x00aaaa,
    0xaaaaaa,
    0x555555,
    0xff5555,
    0x55ff55,
    0x5555ff,
    0xffff55,
    0xff55ff,
    0x55ffff,
    0xffffff,
    0x000000
  }
  -- programmatically generate the rest since they follow a pattern
  local function inc(n)
    if n >= 0xff then
      return 0
    else
      return n + 40
    end
  end
  local function pack(r,g,b)
    return bit32.lshift(r, 16) + bit32.lshift(g, 8) + b
  end
  local r, g, b = 0x5f, 0, 0
  local i = 0
  repeat
    table.insert(palette, pack(r, g, b))
    b = inc(b)
    if b == 0 then
      b = 0x5f
      g = inc(g)
    end
    if g == 0 then
      g = 0x5f
      r = inc(r)
    end
    if r == 0 then
      break
    end
  until r == 0xff and g == 0xff and b == 0xff
  table.insert(palette, pack(r,g,b))
  for i=0x8, 0xee, 10 do
    table.insert(palette, pack(i,i,i))
  end
  local min, max = math.min, math.max
  -- vt.new(gpu:string, screen:string): table
  --   This function takes a gpu and screen address and returns a (non-buffered!) stream.
  function vt.new(gpu, screen)
    checkArg(1, gpu, "string")
    checkArg(2, screen, "string")
    if component.type(gpu) ~= "gpu" or component.type(screen) ~= "screen" then
      return nil, "invalid gpu/screen"
    end
    gpu = component.proxy(gpu)
    gpu.bind(screen)
    local mode = 0
    -- TTY modes:
    -- 0: regular text
    -- 1: received '\27'
    -- 2: received '\27[', in escape
    local rb = ""
    local wb = ""
    local nb = ""
    local ec = true -- local echo
    local lm = true -- line mode
    local cx, cy = 0, 0
    local fg, bg = colors[8], colors[1]
    local w, h = gpu.maxResolution()
    gpu.setResolution(w, h)
    
    local function scroll(n)
      gpu.copy(1, 1, w, h, 0, -n)
      gpu.fill(1, h - n, w, n, " ")
      cy = cy - n
    end

    local function checkCursor()
      if cx > w then cx, cy = 1, cy + 1 end
      if cy > h then scroll(1) cy = h end
      if cx < 1 then cx = w cy = cy - 1 end
      if cy < 1 then cy = 1 end
    end

    local function flushwb()
      while unicode.len(wb) > 0 do
        checkCursor()
        local ln = unicode.sub(wb, 1, w - cx + 1)
        if ec then gpu.set(cx, cy, ln) cx = cx + unicode.len(ln) end
      end
    end

    local stream = {}

    local p = {}
    -- stream:write(str:string): boolean or nil, string
    --   Write a string to the stream. The string will be parsed for vt100 codes.
    function stream:write(str)
      checkArg(1, str, "string")
      if self.closed then
        return kio.error("IO_ERROR")
      end
      str = str:gsub("\8", "\27[D")
      local _c = gpu.get(cx, cy)
      gpu.setForeground(fg)
      gpu.setBackground(bg)
      gpu.set(cx, cy, _c)
      for c in str:gmatch(".") do
        if mode == 0 then
          if c == "\n" then
            flushwb()
          elseif c == "\t" then
            wb = wb .. (" "):rep(max(1, (cx + 4) % 8))
          elseif c == "\27" then
            flush()
            mode = 1
          elseif c == "\7" then -- ascii BEL
            computer.beep(".")
          else
            wb = wb .. c
          end
        elseif mode == 1 then
          if c == "[" then
            mode = 2
          else
            mode = 0
          end
        elseif mode == 2 then
          if c:match("[%d]") then
            nb = nb .. c
          elseif c == ";" then
            if #nb > 0 then
              p[#p+1] = tonumber(nb) or 0
              nb = ""
            end
          else
            mode = 0
            if #nb > 0 then
              p[#p+1] = tonumber(nb)
              nb = ""
            end
            if c == "A" then
              cy = cy + max(0, p[1] or 1)
            elseif c == "B" then
              cy = cy - max(0, p[1] or 1)
            elseif c == "C" then
              cx = cx + max(0, p[1] or 1)
            elseif c == "D" then
              cx = cx - max(0, p[1] or 1)
            elseif c == "E" then
              cx, cy = 1, cy + max(0, p[1] or 1)
            elseif c == "F" then
              cx, cy = 1, cy - max(0, p[1] or 1)
            elseif c == "G" then
              cx = min(w, max(p[1] or 1))
            elseif c == "H" or c == "f" then
              cx, cy = min(w, max(0, p[2] or 1)), min(h, max(0, p[1] or 1))
            elseif c == "J" then
              local n = p[1] or 0
              if n == 0 then
                gpu.fill(cx, cy, w, 1, " ")
                gpu.fill(cx, cy + 1, h, " ")
              elseif n == 1 then
                gpu.fill(1, 1, w, cy - 1, " ")
                gpu.fill(cx, cy, w, 1, " ")
              elseif n == 2 then
                gpu.fill(1, 1, w, h, " ")
              end
            elseif c == "K" then
              local n = p[1] or 0
              if n == 0 then
                gpu.fill(cx, cy, w, 1, " ")
              elseif n == 1 then
                gpu.fill(1, cy, cx, 1, " ")
              elseif n == 2 then
                gpu.fill(1, cy, w, 1, " ")
              end
            elseif c == "S" then
              scroll(max(0, p[1] or 1))
              checkCursor()
            elseif c == "T" then
              scroll(-max(0, p[1] or 1))
              checkCursor()
            elseif c == "m" then
              local ic = false -- in RGB-color escape
              local icm = 0 -- RGB-color mode: 2 = 240-color, 5 = 24-bit R;G;B
              local icc = 0 -- the color
              local icv = 0 -- fg or bg?
              local icn = 0 -- which segment we're on: 1 = R, 2 = G, 3 = B
              p[1] = p[1] or 0
              for i=1, #p, 1 do
                local n = p[i]
                if ic then
                  if icm == 0 then
                    icm = n
                  elseif icm == 2 then
                    if icn < 3 then
                      icn = icn + 1
                      icc = icc + bit32.lshift(n, 8 * (3 - icn))
                    else
                      ic = false
                      if icv == 1 then
                        bg = icc
                      else
                        fg = icc
                      end
                    end
                  elseif icm == 5 then
                    if palette[n] then
                      icc = palette[n]
                    end
                    ic = false
                    if icv == 1 then
                      bg = icc
                    else
                      fg = icc
                    end
                  end
                else
                  icm = 0
                  icc = 0
                  icv = 0
                  icn = 0
                  if n == 0 then -- reset terminal attributes
                    fg, bg = colors[8], colors[1]
                    ec = true
                    lm = true
                  elseif n == 8 then -- disable local echo
                    ec = false
                  elseif n == 28 then -- enable local echo
                    ec = true
                  elseif n > 29 and n < 38 then -- foreground color
                    fg = colors[n - 29]
                  elseif n > 39 and n < 48 then -- background color
                    bg = colors[n - 39]
                  elseif n == 38 then -- 256/24-bit color, foreground
                    ic = true
                    icv = 0
                  elseif n == 48 then -- 256/24-bit color, background
                    ic = true
                    icv = 1
                  elseif n == 39 then -- default foreground
                    fg = colors[8]
                  elseif n == 49 then -- default background
                    bg = colors[1]
                  elseif n > 89 and n < 98 then -- bright foreground
                    fg = bright[n - 89]
                  elseif n > 99 and n < 108 then -- bright background
                    bg = bright[n - 99]
                  elseif n == 108 then -- disable line mode
                    lm = false
                  elseif n == 128 then -- enable line mode
                    lm = true
                  end
                end
              end
            elseif c == "n" then
              if p[1] and p[1] == 6 then
                rb = rb .. string.format("\27[%s;%sR", cy, cx)
              end
            end
          end
        end
        flushwb()
        checkCursor()
        local _c, f, b = gpu.get(cx, cy)
        gpu.setForeground(b)
        gpu.setBackground(f)
        gpu.set(cx, cy, _c)
        gpu.setForeground(fg)
        gpu.setBackground(bg)
        return true
      end
    end

    -- stream:read([n:number]): string or nil, string
    --   Returns characters from the keyboard input buffer.
    function stream:read(n)
      checkArg(1, n, "number", "nil")
      if self.closed then
        return kio.error("IO_ERROR")
      end
      if n == math.huge then
        rb = ""
        return rb
      end
      if n and lm then
        while (unicode.len(rb) < n) do
          coroutine.yield()
        end
      else
        n = n or 0
        while not (unicode.len(rb) < n and rb:find("\n")) do
          coroutine.yield()
        end
      end
      n = n or rb:find("\n")
      local ret = rb:sub(1, n)
      rb = rb:sub(n + 1)
      return ret
    end
    
    local sub = {
      [200] = "\27[A",
      [201] = "\27[5~",
      [209] = "\27[6~",
      [203] = "\27[D",
      [205] = "\27[C",
      [208] = "\27[B"
    }
    -- key input listener. this is a kernel event listener, so it should be
    -- faster than using a thread, especially per-terminal.
    local function listener(sig, addr, char, code)
      if addr == screen then
        if char == 0 then
          char = sub[code] or ""
        elseif char == 8 and lm then
          rb = unicode.sub(rb, 1, unicode.len(rb) - 1)
          stream:write("\8 \8")
          return true
        else
          char = unicode.char(char)
        end
        rb = rb .. char
        stream:write((char:gsub("\27", "^")))
      end
    end

    local id = k.evt.register("key_down", listener)
    -- we should unregister the listener when the terminal stream is closed to
    -- help memory usage and responsiveness
    -- stream:close(): boolean
    --   Close the terminal stream. Unregisters the key listener.
    function stream:close()
      self.closed = true
      k.evt.unregister(id)
      return true
    end

    return stream
  end
  k.vt = vt
end

kio.panic("premature exit!")
