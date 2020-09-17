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
local kargs = {}

for word in cmdline:gmatch("[^%s]+") do
  local k, v = word:match("(.-)=(.+)")
  k, v = k or word, v or true
  kargs[k] = v
end

_G._KINFO = {
  name    = "Paragon",
  version = "0.1.0",
  built   = "2020/09/16",
  builder = "ocawesome101@manjaro-pbp"
}

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

  kio.gpu = gpu
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
  if not msg then msg = level level = nil end
  level = level or kio.loglevels.INFO
  for line in msg:gmatch("[^\n]+") do
    local mesg = string.format("[%5.05f] [%s] %s", computer.uptime(), kio.levels[level], line)
    if level >= kargs.loglevel then
      kio.console(mesg)
    end
    table.insert(dmesg, mesg)
  end
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

-- simple buffer implementation --

kio.dmesg(kio.loglevels.INFO, "ksrc/buffer.lua")

do
  local buf = {}
  local mt = {
    __index = buf,
    __metatable = "file"
  }

  function buf.new(stream, mode)
    checkArg(1, stream, "table")
    checkArg(2, mode, "string")
    local new = {
      stream = stream,
      mode = {},
      tty = false, -- if true, then returned stream is not buffered
      rbuf = "",
      wbuf = "",
      closed = false,
      bufsize = 512
    }
    for c in mode:gmatch(".") do
      new.mode[c] = true
    end
    return setmetatable(new, mt)
  end

  function buf:read(fmt)
    checkArg(1, fmt, "number", "string", "nil")
    fmt = fmt or "l"
    if type(fmt) == "string" then
      fmt = fmt:gsub("%*", "")
    end
    if fmt == "a" then
      return self:readNum(math.huge)
    elseif fmt == "l" then
      local ln = ""
      repeat
        local c = self:readNum(1)
        if c and c ~= "\n" then ln = ln .. c end
      until c == "\n" or not c
      return ln
    elseif fmt == "L" then
      local ln = ""
      repeat
        local c = self:readNum(1)
        if c then ln = ln .. c end
      until c == "\n" or not c
      return ln
    elseif type(fmt) == "number" then
      return self:readNum(fmt)
    else
      error("bad argument #1: invalid format")
    end
  end

  function buf:write(...)
    local args = table.pack(...)
    for i=1, args.n, 1 do
      checkArg(i, dat, "string", "number")
    end
    local dat = table.concat(args)
    self.wbuf = self.wbuf .. dat
    if #self.wbuf > self.bufsize then
      local wrt = self.wbuf
      self.wbuf = ""
      self.stream:write(wrt)
    end
  end

  function buf:flush()
    self.stream:write(self.wbuf)
    self.wbuf = ""
    return true
  end

  function buf:close()
    self:flush()
    self.closed = true
  end

  function buf:readNum(n)
    checkArg(1, n, "number")
    if #self.rbuf < n then
      local reqN = n ~= math.huge and n + math.min(0, self.bufsize - n) or n
      repeat
        local dat = self.stream:read(reqN)
        if not dat then reqN = 0
         else reqN = reqN - #dat
              self.rbuf = self.rbuf .. dat
        end
      until reqN <= 0
    end
    if n == math.huge then n = #self.rbuf end
    local ret = self.rbuf:sub(1, n)
    self.rbuf = self.rbuf:sub(n + 1)
    return ret
  end

  kio.buffer = buf
end



-- kernel drivers

kio.dmesg(kio.loglevels.INFO, "ksrc/kdrv.lua")

local kdrv = {}

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


-- Minitel

kio.dmesg(kio.loglevels.INFO, "ksrc/net/minitel.lua")



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

kio.dmesg(kio.loglevels.INFO, "ksrc/util.lua")

function table.copy(t)
  checkArg(1, t, "table")
  local seen = {}
  local function copy(tbl)
    local ret = {}
    tbl = tbl or {}
    for k, v in pairs(tbl) do
      if type(v) == "table" and not seen[v] then
        seen[v] = true
        ret[k] = copy(v)
      else
        ret[k] = v
      end
    end
    return ret
  end
  return copy(t)
end

-- kernel api

kio.dmesg(kio.loglevels.INFO, "ksrc/kapi.lua")
_G.k = {}
k.args    = kargs
k.io      = kio
k.info    = _KINFO
k.process = sched
k.drv     = kdrv

-- various hooks called on different actions --

do
  local hooks = {}
  hooks.target = {}
  function hooks.add(k, v)
    checkArg(1, k, "string")
    checkArg(2, v, "function")
    hooks[k] = hooks[k] or setmetatable({}, {__call = function(self, ...) for k, v in pairs(self) do pcall(v, ...) end end})
    table.insert(hooks[k], v)
    return true
  end
  function hooks.call(k, ...)
    checkArg(1, k, "string")
    if hooks[k] then
      for k,v in pairs(hooks[k]) do
        pcall(v, ...)
      end
    end
  end
  k.hooks = hooks
end

do
  -- some default hooks
  local function sbld(iomt)
    function k.sb.load(x, name, mode, env)
      return load(x, name, mode, env or k.sb)
    end
    setmetatable(k.sb.io, iomt)
    k.sb.k.vfs = table.copy(vfs)
    k.sb.k.iomt = nil
    k.sb.k.sched.loop = nil
    k.sb.k.io.gpu = kio.gpu -- otherwise metatable weirdness
  end
  k.hooks.add("sandbox", sbld)
end

-- security :^) --

kio.dmesg("ksrc/security.lua")

k.security = {}

-- users --

kio.dmesg("ksrc/security/users.lua")

do
  -- NOTE: processes cannot, and I repeat, CANNOT authenticate themselves as
  -- NOTE: a user other than their current one. This simplifies certain things.
  local users = {}
  local upasswd = {}
  
  -- users.prime(passwd:table): boolean or nil, string
  --   Prime the 'users' API with data from a passwd file, usually /etc/passwd.
  function users.prime(passwd)
    checkArg(1, passwd, "table")
    if not passwd[0] and passwd[0].hash and passwd[0].name and passwd[0].home
                                                                            then
      return nil, "no root password definition"
    end
    users.prime = nil
    k.sb.k.security.users.prime = nil
    upasswd = passwd
    return true
  end

  local msgs = {
    "no such user",
    "invalid credentials",
    "permission denied"
  }

  function users.checkAuth(uid, passwd, _)
    checkArg(1, uid, "number")
    checkArg(2, passwd, "string")
    if not upasswd[uid] then
      return nil, _ and 1 or msgs[1]
    end
    if string.hex(k.sha3.sha512(passwd)) == upasswd[uid].hash then
      return true
    else
      return nil, _ and 2 or msgs[2]
    end
  end

  function users.spawnAs(uid, passwd, func, name)
    checkArg(1, uid, "number")
    checkArg(2, passwd, "string")
    checkArg(3, func, "function")
    checkArg(4, name, "string")
    local ok, code = users.checkAuth(uid, passwd, true)
    if not ok then
      return nil, msgs[code <= 1 and code or 3]
    end
    local pid = k.sched.spawn(func, name, nil, uid)
    repeat
      coroutine.yield()
    until not k.sched.getinfo(pid)
    return true
  end

  function users.user()
    return (k.sched.getinfo() or {}).owner or 0
  end

  k.security.users = users
end

-- add sandbox hook to prevent userspace from easily spoofing user IDs
do
  k.hooks.add("sandbox", function()
    function k.sb.sched.spawn(a,b,c)
      return k.sched.spawn(a,b,c)
    end
  end)
end


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
    local resumed = computer.uptime()
    kio.dmesg(kio.loglevels.DEBUG, "resume: process" .. self.pid)
    for i=1, #self.threads, 1 do
      kio.dmesg(kio.loglevels.DEBUG, "process " .. self.pid .. ": resuming thread " .. i)
      local thd = self.threads[i]
      local ok, ec = coroutine.resume(thd.coro, ...)
      if (not ok) or coroutine.status(thd.coro) == "dead" then
        kio.dmesg(kio.loglevels.DEBUG, "process " .. self.pid .. ": thread died: " .. i)
        self.threads[i] = nil
        computer.pushSignal("thread_died", self.pid, (type(ec) == "string" and 1 or ec), type(ec) == "string" and ec)
      end
      -- TODO: this may result in incorrect yield timeouts with multiple threads
      if type(ec) == "number" then
        local nd = ec + computer.uptime()
        if nd < self.deadline then
          self.deadline = nd
        end
      else
        kio.dmesg(kio.loglevels.DEBUG, tostring(ec))
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
      env = self.env,
      owner = self.owner,
      started = self.started,
      runtime = self.runtime,
      threads = self.threads,
      deadline = self.deadline,
      sighandlers = self.sighandlers,
      stdin = process.stdin, -- convenience
      stdout = process.stdout,
      stderr = process.stderr
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
  -- TODO: proper process timeouts
  local timeout = tonumber(kargs["scheduler.timeout"]) or 0.5

  -- k.sched.spawn(func:function, name:string[, priority:number]): table
  --   Spawns a process, adding `func` to its threads.
  function s.spawn(func, name, priority, INTERNAL_UNDOCUMENTED_ARGUMENT)
    checkArg(1, func, "function")
    checkArg(2, name, "string")
    checkArg(3, priority, "number", "nil")
    last = last + 1
    local p = procs[current]
    local new = process.new {
      pid = last,
      parent = current,
      priority = priority or math.huge,
      env = p and table.copy(p.env) or {},
      stdin = p and p.io.stdin or {},
      stdout = p and p.io.stdout or {},
      stderr = p and p.io.stderr or {},
      owner = INTERNAL_UNDOCUMENTED_ARGUMENT
    }
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
    local proc = procs[pid]
    if proc.owner == s.getinfo().owner or s.getinfo().owner == 0 then
      proc:signal(sig)
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

  function s.loop()
    s.loop = nil
    local sig
    kio.dmesg(kio.loglevels.DEBUG, "starting scheduler loop")
    while #procs > 0 do
      sig = table.pack(computer.pullSignal(timeout))
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
          kio.dmesg("process died: " .. proc.pid)
          computer.pushSignal("process_died", proc.pid, proc.name)
          procs[proc.pid] = nil
        end
      end
    end
    kio.panic("All processes died!")
  end
  k.sched = s
end

-- buffered file I/O and misc other --

kio.dmesg(kio.loglevels.INFO, "ksrc/io.lua")

do
  local io = {}
  _G.io = io

  local vfs = vfs

  local iomt = {
    __index = function(self, key)
      local info = k.sched.getinfo()
      if key == "stdin" then
        return info:stdin()
      elseif key == "stdout" then
        return info:stdout()
      elseif key == "stderr" then
        return info:stderr()
      end
    end,
    __metatable = {}
  }
  k.iomt = iomt
  setmetatable(io, iomt)

  local st = {}
  function st:read(n)
    return self.node:read(self.fd, n)
  end

  function st:write(d)
    return self.node:write(self.fd, d)
  end

  function st:close()
    return self.node:close(self.fd)
  end

  local function streamify(node, fd)
    local new = {
      node = node,
      fd = fd
    }
    return setmetatable(new, {__index = st})
  end
  
  -- io.open(file:string[, mode:string]): table or nil, string
  --   Returns a buffered file handle to 
  function io.open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string", "nil")
    local node, path = vfs.resolve(file)
    if not node then
      return nil, path
    end
    local handle, err = node:open(path, mode)
    if not handle then
      return nil, err
    end
    local stream = streamify(node, handle)
    return kio.buffer.new(stream, mode)
  end

  function io.input(file)
    local info = k.sched.getinfo()
    return info:stdin(file)
  end

  function io.output(file)
    local info = k.sched.getinfo()
    return info:stdout(file)
  end

  function io.read(...)
    return io.stdin:read(...)
  end

  function io.write(...)
    return io.stdout:write(...)
  end

  --TODO: flesh out io, maybe in userspace?
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

kio.dmesg(kio.loglevels.INFO, "ksrc/misc/sha3.lua")

do
-- Copyright (c) 2014  Joseph Wallace
-- Copyright (c) 2015  Phil Leblanc
-- License: MIT - see LICENSE file
------------------------------------------------------------

-- 170612 SHA-3 padding fixed.
-- (reported by Michael Rosenberg https://github.com/doomrobo)

-- 150827 original code modified and optimized
-- (more than 2x performance improvement for sha3-512) --phil

-- Directly devived from a Keccak implementation by Joseph Wallace
-- published on the Lua mailing list in 2014
-- http://lua-users.org/lists/lua-l/2014-03/msg00905.html


------------------------------------------------------------
-- sha3 / keccak

local char	= string.char
local concat	= table.concat
local spack, sunpack = string.pack, string.unpack

-- the Keccak constants and functionality

local ROUNDS = 24

local roundConstants = {
0x0000000000000001,
0x0000000000008082,
0x800000000000808A,
0x8000000080008000,
0x000000000000808B,
0x0000000080000001,
0x8000000080008081,
0x8000000000008009,
0x000000000000008A,
0x0000000000000088,
0x0000000080008009,
0x000000008000000A,
0x000000008000808B,
0x800000000000008B,
0x8000000000008089,
0x8000000000008003,
0x8000000000008002,
0x8000000000000080,
0x000000000000800A,
0x800000008000000A,
0x8000000080008081,
0x8000000000008080,
0x0000000080000001,
0x8000000080008008
}

local rotationOffsets = {
-- ordered for [x][y] dereferencing, so appear flipped here:
{0, 36, 3, 41, 18},
{1, 44, 10, 45, 2},
{62, 6, 43, 15, 61},
{28, 55, 25, 21, 56},
{27, 20, 39, 8, 14}
}



-- the full permutation function
local function keccakF(st)
	local permuted = st.permuted
	local parities = st.parities
	for round = 1, ROUNDS do
--~ 		local permuted = permuted
--~ 		local parities = parities

		-- theta()
		for x = 1,5 do
			parities[x] = 0
			local sx = st[x]
			for y = 1,5 do parities[x] = parities[x] ~ sx[y] end
		end
		--
		-- unroll the following loop
		--for x = 1,5 do
		--	local p5 = parities[(x)%5 + 1]
		--	local flip = parities[(x-2)%5 + 1] ~ ( p5 << 1 | p5 >> 63)
		--	for y = 1,5 do st[x][y] = st[x][y] ~ flip end
		--end
		local p5, flip, s
		--x=1
		p5 = parities[2]
		flip = parities[5] ~ (p5 << 1 | p5 >> 63)
		s = st[1]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=2
		p5 = parities[3]
		flip = parities[1] ~ (p5 << 1 | p5 >> 63)
		s = st[2]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=3
		p5 = parities[4]
		flip = parities[2] ~ (p5 << 1 | p5 >> 63)
		s = st[3]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=4
		p5 = parities[5]
		flip = parities[3] ~ (p5 << 1 | p5 >> 63)
		s = st[4]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=5
		p5 = parities[1]
		flip = parities[4] ~ (p5 << 1 | p5 >> 63)
		s = st[5]
		for y = 1,5 do s[y] = s[y] ~ flip end

		-- rhopi()
		for y = 1,5 do
			local py = permuted[y]
			local r
			for x = 1,5 do
				s, r = st[x][y], rotationOffsets[x][y]
				py[(2*x + 3*y)%5 + 1] = (s << r | s >> (64-r))
			end
		end

		-- chi() - unroll the loop
		--for x = 1,5 do
		--	for y = 1,5 do
		--		local combined = (~ permuted[(x)%5 +1][y]) & permuted[(x+1)%5 +1][y]
		--		st[x][y] = permuted[x][y] ~ combined
		--	end
		--end

		local p, p1, p2
		--x=1
		s, p, p1, p2 = st[1], permuted[1], permuted[2], permuted[3]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=2
		s, p, p1, p2 = st[2], permuted[2], permuted[3], permuted[4]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=3
		s, p, p1, p2 = st[3], permuted[3], permuted[4], permuted[5]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=4
		s, p, p1, p2 = st[4], permuted[4], permuted[5], permuted[1]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=5
		s, p, p1, p2 = st[5], permuted[5], permuted[1], permuted[2]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end

		-- iota()
		st[1][1] = st[1][1] ~ roundConstants[round]
	end
end


local function absorb(st, buffer)

	local blockBytes = st.rate / 8
	local blockWords = blockBytes / 8

	-- append 0x01 byte and pad with zeros to block size (rate/8 bytes)
	local totalBytes = #buffer + 1
	-- for keccak (2012 submission), the padding is byte 0x01 followed by zeros
	-- for SHA3 (NIST, 2015), the padding is byte 0x06 followed by zeros

	-- Keccak:
	-- buffer = buffer .. ( '\x01' .. char(0):rep(blockBytes - (totalBytes % blockBytes)))

	-- SHA3:
	buffer = buffer .. ( '\x06' .. char(0):rep(blockBytes - (totalBytes % blockBytes)))
	totalBytes = #buffer

	--convert data to an array of u64
	local words = {}
	for i = 1, totalBytes - (totalBytes % 8), 8 do
		words[#words + 1] = sunpack('<I8', buffer, i)
	end

	local totalWords = #words
	-- OR final word with 0x80000000 to set last bit of state to 1
	words[totalWords] = words[totalWords] | 0x8000000000000000

	-- XOR blocks into state
	for startBlock = 1, totalWords, blockWords do
		local offset = 0
		for y = 1, 5 do
			for x = 1, 5 do
				if offset < blockWords then
					local index = startBlock+offset
					st[x][y] = st[x][y] ~ words[index]
					offset = offset + 1
				end
			end
		end
		keccakF(st)
	end
end


-- returns [rate] bits from the state, without permuting afterward.
-- Only for use when the state will immediately be thrown away,
-- and not used for more output later
local function squeeze(st)
	local blockBytes = st.rate / 8
	local blockWords = blockBytes / 4
	-- fetch blocks out of state
	local hasht = {}
	local offset = 1
	for y = 1, 5 do
		for x = 1, 5 do
			if offset < blockWords then
				hasht[offset] = spack("<I8", st[x][y])
				offset = offset + 1
			end
		end
	end
	return concat(hasht)
end


-- primitive functions (assume rate is a whole multiple of 64 and length is a whole multiple of 8)

local function keccakHash(rate, length, data)
	local state = {	{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
	}
	state.rate = rate
	-- these are allocated once, and reused
	state.permuted = { {}, {}, {}, {}, {}, }
	state.parities = {0,0,0,0,0}
	absorb(state, data)
	return squeeze(state):sub(1,length/8)
end

-- output raw bytestrings
local function keccak256Bin(data) return keccakHash(1088, 256, data) end
local function keccak512Bin(data) return keccakHash(576, 512, data) end

k.sha3 = {
	sha256 = keccak256Bin,
	sha512 = keccak512Bin,
}
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

kio.dmesg(kio.loglevels.INFO, "ksrc/misc/ec25519.lua")

do
-- Copyright (c) 2015  Phil Leblanc  -- see LICENSE file

------------------------------------------------------------
--[[
ec25519 - curve25519 scalar multiplication
Ported to Lua from the original C tweetnacl implementation,
(public domain, by Dan Bernstein, Tanja Lange et al
see http://tweetnacl.cr.yp.to/ )
To make debug and validation easier, the original code structure
and function names have been conserved as much as possible.
]]

------------------------------------------------------------

-- set25519() not used

local function car25519(o)
	local c
	for i = 1, 16 do
		o[i] = o[i] + 65536 -- 1 << 16
		-- lua ">>" doesn't perform sign extension...
		-- so the following >>16 doesn't work with negative numbers!!
		-- ...took a bit of time to find this one :-)
		-- c = o[i] >> 16
		c = o[i] // 65536
		if i < 16 then
			o[i+1] = o[i+1] + (c - 1)
		else
			o[1] = o[1] + 38 * (c - 1)
		end
		o[i] = o[i] - (c << 16)
	end
end --car25519()

local function sel25519(p, q, b)
	local c = ~(b-1)
	local t
	for i = 1, 16 do
		t = c & (p[i] ~ q[i])
		p[i] = p[i] ~ t
		q[i] = q[i] ~ t
	end
end --sel25519

local function pack25519(o, n)
	-- out o[32], in n[16]
	local m, t = {}, {}
	local b
	for i = 1, 16 do t[i] = n[i] end
	car25519(t)
	car25519(t)
	car25519(t)
	for _ = 1, 2 do
		m[1] = t[1] - 0xffed
		for i = 2, 15 do
			m[i] = t[i] - 0xffff - ((m[i-1] >> 16) & 1)
			m[i-1] = m[i-1] & 0xffff
		end
		m[16] = t[16] - 0x7fff - ((m[15] >> 16) & 1)
		b = (m[16] >> 16) & 1
		m[15] = m[15] & 0xffff
		sel25519(t, m, 1-b)
	end
	for i = 1, 16 do
		o[2*i-1] = t[i] & 0xff
		o[2*i] = t[i] >> 8
	end
end -- pack25519

-- neq25519() not used
-- par25519() not used

local function unpack25519(o, n)
	-- out o[16], in n[32]
	for i = 1, 16 do
		o[i] = n[2*i-1] + (n[2*i] << 8)
	end
	o[16] = o[16] & 0x7fff
end -- unpack25519

local function A(o, a, b) --add
	for i = 1, 16 do o[i] = a[i] + b[i] end
end

local function Z(o, a, b) --sub
	for i = 1, 16 do o[i] = a[i] - b[i] end
end

local function M(o, a, b) --mul  gf, gf -> gf
	local t = {}
	for i = 1, 32 do t[i] = 0  end
	for i = 1, 16 do
		for j = 1, 16 do
			t[i+j-1] = t[i+j-1] + (a[i] * b[j])
		end
	end
	for i = 1, 15 do t[i] = t[i] + 38 * t[i+16] end
	for i = 1, 16 do o[i] = t[i] end
	car25519(o)
	car25519(o)
end

local function S(o, a)  --square
	M(o, a, a)
end

local function inv25519(o, i)
	local c = {}
	for a = 1, 16 do c[a] = i[a] end
	for a = 253, 0, -1 do
		S(c, c)
		if a ~= 2 and a ~= 4 then M(c, c, i) end
	end
	for a = 1, 16 do o[a] = c[a] end
--~ 	pt(o)
end

--pow2523() not used

local t_121665 = {0xDB41,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0}

local function crypto_scalarmult(q, n, p)
	-- out q[], in n[], in p[]
	local z = {}
	local x = {}
	local a = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
	local b = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
	local c = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
	local d = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
	local e = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
	local f = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
	for i = 1, 31 do z[i] = n[i] end
	z[32] = (n[32] & 127) | 64
	z[1] = z[1] & 248
--~ 	pt(z)
	unpack25519(x, p)
--~ 	pt(x)
	for i = 1, 16 do
		b[i] = x[i]
		a[i] = 0
		c[i] = 0
		d[i] = 0
	end
	a[1] = 1
	d[1] = 1
	for i = 254, 0, -1 do
		local r = (z[(i>>3)+1] >> (i & 7)) & 1
		sel25519(a,b,r)
		sel25519(c,d,r)
		A(e,a,c)
		Z(a,a,c)
		A(c,b,d)
		Z(b,b,d)
		S(d,e)
		S(f,a)
		M(a,c,a)
		M(c,b,e)
		A(e,a,c)
		Z(a,a,c)
		S(b,a)
		Z(c,d,f)
		M(a,c,t_121665)
		A(a,a,d)
		M(c,c,a)
		M(a,d,f)
		M(d,b,x)
		S(b,e)
		sel25519(a,b,r)
		sel25519(c,d,r)
	end
	for i = 1, 16 do
		x[i+16] = a[i]
		x[i+32] = c[i]
		x[i+48] = b[i]
		x[i+64] = d[i]
	end
	-- cannot use pointer arithmetics...
	local x16, x32 = {}, {}
	for i = 1, #x do
		if i > 16 then x16[i-16] = x[i] end
		if i > 32 then x32[i-32] = x[i] end
	end
	inv25519(x32,x32)
	M(x16,x16,x32)
	pack25519(q,x16)
	return 0
end -- crypto_scalarmult

local t_9 = { -- u8 * 32
	9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	}

local function crypto_scalarmult_base(q, n)
	-- out q[], in n[]
	return crypto_scalarmult(q, n, t_9)
end

------------------------------------------------------------------------
-- convenience function (using binary strings instead of byte tables)
--
-- curve point and scalars are represented as 32-byte binary strings
-- (encoded as little endian)

local function scalarmult(n, p)
	-- n, a scalar (little endian) as a 32-byte string
	-- p, a curve point as a 32-byte string
	-- return the scalar product np as a 32-byte string
	local qt, nt, pt = {}, {}, {} 
	for i = 1, 32 do 
		nt[i] = string.byte(n, i) 
		pt[i] = string.byte(p, i) 
	end
	crypto_scalarmult(qt, nt, pt)
	local q = string.char(table.unpack(qt))
	return q
end

-- base: the curve point generator = 9

local base = '\9' .. ('\0'):rep(31)

k.ec25519 = {
	crypto_scalarmult = crypto_scalarmult,
	crypto_scalarmult_base = crypto_scalarmult_base,
	--
	-- convenience function and definition
	--
	scalarmult = scalarmult,
	base = base,
	--
}

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

kio.dmesg(kio.loglevels.INFO, "ksrc/misc/sha2.lua")

do
-- Copyright (c) 2018  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------

--        SHA2-256 and SHA2-512 -- see RFC 6234


-- sha2-256 initially based on code written by Roberto Ierusalimschy
-- for an early Lua 5.3rc with (un)packint() functions.
-- published by  Roberto on the Lua mailing list
-- http://lua-users.org/lists/lua-l/2014-03/msg00851.html
-- can be distributed under the MIT License terms. see:
-- http://lua-users.org/lists/lua-l/2014-08/msg00628.html
--
-- adapted to 5.3 (string.(un)pack()) --phil, 150827
--
-- optimized for performance, 181008. The core permutation
-- for sha2-256 and sha2-512 is lifted from the very good
-- implementation by Egor Skriptunoff, also MIT-licensed. See
-- https://github.com/Egor-Skriptunoff/pure_lua_SHA2


------------------------------------------------------------
-- local declarations

local string, assert = string, assert
local spack, sunpack = string.pack, string.unpack 

------------------------------------------------------------------------
-- sha256

-- Initialize table of round constants
-- (first 32 bits of the fractional parts of the cube roots of the first
-- 64 primes 2..311)
local k256 = {
   0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
   0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
   0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
   0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
   0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
   0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
   0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
   0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
   0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
   0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
   0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
   0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
   0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
   0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
   0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
   0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function pad64(msg, len)
	local extra = 64 - ((len + 1 + 8) % 64)
	len = spack(">I8", len * 8)    -- original len in bits, coded
	msg = msg .. "\128" .. string.rep("\0", extra) .. len
	assert(#msg % 64 == 0)
	return msg
end

local ww256 = {}
	  
local function sha256 (msg)
	msg = pad64(msg, #msg)
	local h1, h2, h3, h4, h5, h6, h7, h8 = 
		0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
	local k = k256
	local w = ww256
	local mlen = #msg
  	-- Process the message in successive 512-bit (64 bytes) chunks:
	for i = 1, mlen, 64 do
		w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8], 
		w[9], w[10], w[11], w[12], w[13], w[14], w[15], w[16]
		= sunpack(">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", msg, i)
		-- mix msg block in state
		for j = 17, 64 do
			local x = w[j - 15]; x = (x << 32) | x
			local y = w[j - 2]; y = (y << 32) | y
			w[j] = (  ((x >> 7) ~ (x >> 18) ~ (x >> 35))
				+ ((y >> 17) ~ (y >> 19) ~ (y >> 42))
				+ w[j - 7] + w[j - 16]  ) & 0xffffffff
		end
		local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
		-- main state permutation
		for j = 1, 64 do
			e = (e << 32) | (e & 0xffffffff)
			local t1 = ((e >> 6) ~ (e >> 11) ~ (e >> 25))
				+ (g ~ e & (f ~ g)) + h + k[j] + w[j]
			h = g
			g = f
			f = e
			e = (d + t1) 
			d = c
			c = b
			b = a
			a = (a << 32) | (a & 0xffffffff)
			a = t1 	+ ((a ~ c) & d ~ a & c) 
				+ ((a >> 2) ~ (a >> 13) ~ (a >> 22))
		end
		h1 = h1 + a
		h2 = h2 + b 
		h3 = h3 + c 
		h4 = h4 + d 
		h5 = h5 + e 
		h6 = h6 + f 
		h7 = h7 + g 
		h8 = h8 + h 
	end
	-- clamp hash to 32-bit words
	h1 = h1 & 0xffffffff
	h2 = h2 & 0xffffffff
	h3 = h3 & 0xffffffff
	h4 = h4 & 0xffffffff
	h5 = h5 & 0xffffffff
	h6 = h6 & 0xffffffff
	h7 = h7 & 0xffffffff
	h8 = h8 & 0xffffffff
	-- return hash as a binary string
	return spack(">I4I4I4I4I4I4I4I4", h1, h2, h3, h4, h5, h6, h7, h8)
end --sha256

------------------------------------------------------------------------
-- sha512

local k512 = {
0x428a2f98d728ae22,0x7137449123ef65cd,0xb5c0fbcfec4d3b2f,0xe9b5dba58189dbbc,
0x3956c25bf348b538,0x59f111f1b605d019,0x923f82a4af194f9b,0xab1c5ed5da6d8118,
0xd807aa98a3030242,0x12835b0145706fbe,0x243185be4ee4b28c,0x550c7dc3d5ffb4e2,
0x72be5d74f27b896f,0x80deb1fe3b1696b1,0x9bdc06a725c71235,0xc19bf174cf692694,
0xe49b69c19ef14ad2,0xefbe4786384f25e3,0x0fc19dc68b8cd5b5,0x240ca1cc77ac9c65,
0x2de92c6f592b0275,0x4a7484aa6ea6e483,0x5cb0a9dcbd41fbd4,0x76f988da831153b5,
0x983e5152ee66dfab,0xa831c66d2db43210,0xb00327c898fb213f,0xbf597fc7beef0ee4,
0xc6e00bf33da88fc2,0xd5a79147930aa725,0x06ca6351e003826f,0x142929670a0e6e70,
0x27b70a8546d22ffc,0x2e1b21385c26c926,0x4d2c6dfc5ac42aed,0x53380d139d95b3df,
0x650a73548baf63de,0x766a0abb3c77b2a8,0x81c2c92e47edaee6,0x92722c851482353b,
0xa2bfe8a14cf10364,0xa81a664bbc423001,0xc24b8b70d0f89791,0xc76c51a30654be30,
0xd192e819d6ef5218,0xd69906245565a910,0xf40e35855771202a,0x106aa07032bbd1b8,
0x19a4c116b8d2d0c8,0x1e376c085141ab53,0x2748774cdf8eeb99,0x34b0bcb5e19b48a8,
0x391c0cb3c5c95a63,0x4ed8aa4ae3418acb,0x5b9cca4f7763e373,0x682e6ff3d6b2b8a3,
0x748f82ee5defb2fc,0x78a5636f43172f60,0x84c87814a1f0ab72,0x8cc702081a6439ec,
0x90befffa23631e28,0xa4506cebde82bde9,0xbef9a3f7b2c67915,0xc67178f2e372532b,
0xca273eceea26619c,0xd186b8c721c0c207,0xeada7dd6cde0eb1e,0xf57d4f7fee6ed178,
0x06f067aa72176fba,0x0a637dc5a2c898a6,0x113f9804bef90dae,0x1b710b35131c471b,
0x28db77f523047d84,0x32caab7b40c72493,0x3c9ebe0a15c9bebc,0x431d67c49c100d4c,
0x4cc5d4becb3e42b6,0x597f299cfc657e2a,0x5fcb6fab3ad6faec,0x6c44198c4a475817
}

local function pad128(msg, len)
	local extra = 128 - ((len + 1 + 8) % 128)
	len = spack(">I8", len * 8)    -- original len in bits, coded
	msg = msg .. "\128" .. string.rep("\0", extra) .. len
	assert(#msg % 128 == 0)
	return msg
end

local ww512 = {}
	  
local function sha512 (msg)
	msg = pad128(msg, #msg)
	local h1, h2, h3, h4, h5, h6, h7, h8 = 
		0x6a09e667f3bcc908, 0xbb67ae8584caa73b,
		0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
		0x510e527fade682d1, 0x9b05688c2b3e6c1f,
		0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
	local k = k512
	local w = ww512 -- 80 * i64 state
	local mlen = #msg
  	-- Process the message as 128-byte blocks:
	-- (this is borrowed to Egor Skriptunoff's pure_lua_SHA2
	-- https://github.com/Egor-Skriptunoff/pure_lua_SHA2)
	for i = 1, mlen, 128 do
		w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8], 
		w[9], w[10], w[11], w[12], w[13], w[14], w[15], w[16]
		= sunpack(">i8i8i8i8i8i8i8i8i8i8i8i8i8i8i8i8", msg, i)
		-- mix msg block in state

		for j = 17, 80 do
			local a = w[j-15]
			local b = w[j-2]
			w[j] = (a >> 1 ~ a >> 7 ~ a >> 8 ~ a << 56 ~ a << 63)
			  + (b >> 6 ~ b >> 19 ~ b >> 61 ~ b << 3 ~ b << 45) 
			  + w[j-7] + w[j-16]
		end
		local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
		-- main state permutation
		for j = 1, 80 do
			local z = (e >> 14 ~ e >> 18 ~ e >> 41 ~ e << 23 
				   ~ e << 46 ~ e << 50) 
				+ (g ~ e & (f ~ g)) + h + k[j] + w[j]
			h = g
			g = f
			f = e
			e = z + d
			d = c
			c = b
			b = a
			a = z + ((a ~ c) & d ~ a & c) 
			      + (a >> 28 ~ a >> 34 ~ a >> 39 ~ a << 25 
				~ a << 30 ~ a << 36)
		end
		h1 = h1 + a
		h2 = h2 + b 
		h3 = h3 + c 
		h4 = h4 + d 
		h5 = h5 + e 
		h6 = h6 + f 
		h7 = h7 + g 
		h8 = h8 + h 
	end
	-- return hash as a binary string
	return spack(">i8i8i8i8i8i8i8i8", h1, h2, h3, h4, h5, h6, h7, h8)
end --sha512

------------------------------------------------------------------------

k.sha2 = {
  sha256 = sha256,
  sha512 = sha512,
}

end

kio.dmesg(kio.loglevels.INFO, "ksrc/misc/sha3.lua")

do
-- Copyright (c) 2014  Joseph Wallace
-- Copyright (c) 2015  Phil Leblanc
-- License: MIT - see LICENSE file
------------------------------------------------------------

-- 170612 SHA-3 padding fixed.
-- (reported by Michael Rosenberg https://github.com/doomrobo)

-- 150827 original code modified and optimized
-- (more than 2x performance improvement for sha3-512) --phil

-- Directly devived from a Keccak implementation by Joseph Wallace
-- published on the Lua mailing list in 2014
-- http://lua-users.org/lists/lua-l/2014-03/msg00905.html


------------------------------------------------------------
-- sha3 / keccak

local char	= string.char
local concat	= table.concat
local spack, sunpack = string.pack, string.unpack

-- the Keccak constants and functionality

local ROUNDS = 24

local roundConstants = {
0x0000000000000001,
0x0000000000008082,
0x800000000000808A,
0x8000000080008000,
0x000000000000808B,
0x0000000080000001,
0x8000000080008081,
0x8000000000008009,
0x000000000000008A,
0x0000000000000088,
0x0000000080008009,
0x000000008000000A,
0x000000008000808B,
0x800000000000008B,
0x8000000000008089,
0x8000000000008003,
0x8000000000008002,
0x8000000000000080,
0x000000000000800A,
0x800000008000000A,
0x8000000080008081,
0x8000000000008080,
0x0000000080000001,
0x8000000080008008
}

local rotationOffsets = {
-- ordered for [x][y] dereferencing, so appear flipped here:
{0, 36, 3, 41, 18},
{1, 44, 10, 45, 2},
{62, 6, 43, 15, 61},
{28, 55, 25, 21, 56},
{27, 20, 39, 8, 14}
}



-- the full permutation function
local function keccakF(st)
	local permuted = st.permuted
	local parities = st.parities
	for round = 1, ROUNDS do
--~ 		local permuted = permuted
--~ 		local parities = parities

		-- theta()
		for x = 1,5 do
			parities[x] = 0
			local sx = st[x]
			for y = 1,5 do parities[x] = parities[x] ~ sx[y] end
		end
		--
		-- unroll the following loop
		--for x = 1,5 do
		--	local p5 = parities[(x)%5 + 1]
		--	local flip = parities[(x-2)%5 + 1] ~ ( p5 << 1 | p5 >> 63)
		--	for y = 1,5 do st[x][y] = st[x][y] ~ flip end
		--end
		local p5, flip, s
		--x=1
		p5 = parities[2]
		flip = parities[5] ~ (p5 << 1 | p5 >> 63)
		s = st[1]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=2
		p5 = parities[3]
		flip = parities[1] ~ (p5 << 1 | p5 >> 63)
		s = st[2]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=3
		p5 = parities[4]
		flip = parities[2] ~ (p5 << 1 | p5 >> 63)
		s = st[3]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=4
		p5 = parities[5]
		flip = parities[3] ~ (p5 << 1 | p5 >> 63)
		s = st[4]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=5
		p5 = parities[1]
		flip = parities[4] ~ (p5 << 1 | p5 >> 63)
		s = st[5]
		for y = 1,5 do s[y] = s[y] ~ flip end

		-- rhopi()
		for y = 1,5 do
			local py = permuted[y]
			local r
			for x = 1,5 do
				s, r = st[x][y], rotationOffsets[x][y]
				py[(2*x + 3*y)%5 + 1] = (s << r | s >> (64-r))
			end
		end

		-- chi() - unroll the loop
		--for x = 1,5 do
		--	for y = 1,5 do
		--		local combined = (~ permuted[(x)%5 +1][y]) & permuted[(x+1)%5 +1][y]
		--		st[x][y] = permuted[x][y] ~ combined
		--	end
		--end

		local p, p1, p2
		--x=1
		s, p, p1, p2 = st[1], permuted[1], permuted[2], permuted[3]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=2
		s, p, p1, p2 = st[2], permuted[2], permuted[3], permuted[4]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=3
		s, p, p1, p2 = st[3], permuted[3], permuted[4], permuted[5]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=4
		s, p, p1, p2 = st[4], permuted[4], permuted[5], permuted[1]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=5
		s, p, p1, p2 = st[5], permuted[5], permuted[1], permuted[2]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end

		-- iota()
		st[1][1] = st[1][1] ~ roundConstants[round]
	end
end


local function absorb(st, buffer)

	local blockBytes = st.rate / 8
	local blockWords = blockBytes / 8

	-- append 0x01 byte and pad with zeros to block size (rate/8 bytes)
	local totalBytes = #buffer + 1
	-- for keccak (2012 submission), the padding is byte 0x01 followed by zeros
	-- for SHA3 (NIST, 2015), the padding is byte 0x06 followed by zeros

	-- Keccak:
	-- buffer = buffer .. ( '\x01' .. char(0):rep(blockBytes - (totalBytes % blockBytes)))

	-- SHA3:
	buffer = buffer .. ( '\x06' .. char(0):rep(blockBytes - (totalBytes % blockBytes)))
	totalBytes = #buffer

	--convert data to an array of u64
	local words = {}
	for i = 1, totalBytes - (totalBytes % 8), 8 do
		words[#words + 1] = sunpack('<I8', buffer, i)
	end

	local totalWords = #words
	-- OR final word with 0x80000000 to set last bit of state to 1
	words[totalWords] = words[totalWords] | 0x8000000000000000

	-- XOR blocks into state
	for startBlock = 1, totalWords, blockWords do
		local offset = 0
		for y = 1, 5 do
			for x = 1, 5 do
				if offset < blockWords then
					local index = startBlock+offset
					st[x][y] = st[x][y] ~ words[index]
					offset = offset + 1
				end
			end
		end
		keccakF(st)
	end
end


-- returns [rate] bits from the state, without permuting afterward.
-- Only for use when the state will immediately be thrown away,
-- and not used for more output later
local function squeeze(st)
	local blockBytes = st.rate / 8
	local blockWords = blockBytes / 4
	-- fetch blocks out of state
	local hasht = {}
	local offset = 1
	for y = 1, 5 do
		for x = 1, 5 do
			if offset < blockWords then
				hasht[offset] = spack("<I8", st[x][y])
				offset = offset + 1
			end
		end
	end
	return concat(hasht)
end


-- primitive functions (assume rate is a whole multiple of 64 and length is a whole multiple of 8)

local function keccakHash(rate, length, data)
	local state = {	{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
	}
	state.rate = rate
	-- these are allocated once, and reused
	state.permuted = { {}, {}, {}, {}, {}, }
	state.parities = {0,0,0,0,0}
	absorb(state, data)
	return squeeze(state):sub(1,length/8)
end

-- output raw bytestrings
local function keccak256Bin(data) return keccakHash(1088, 256, data) end
local function keccak512Bin(data) return keccakHash(576, 512, data) end

k.sha3 = {
	sha256 = keccak256Bin,
	sha512 = keccak512Bin,
}
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
        return "", err
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
          kio.dmesg(kio.loglevels.ERROR, files[i]..": "..ret)
        end
      end
    end
  end
end

-- load the fstab from the specified rootfs and mount filesystems accordingly
-- from here on we work with the real rootfs, not the initfs

kio.dmesg(kio.loglevels.INFO, "ksrc/fstab.lua")

-- mount the rootfs
if not kargs.keep_initfs then
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

  -- vt.new(gpu:string, screen:string): table OR vt.new(gpu:table[, screen:string]): table
  --   This function takes a gpu and screen address and returns a (non-buffered!) stream.
  function vt.new(gpu, screen)
    checkArg(1, gpu, "string", "table")
    checkArg(2, screen, "string", "nil")
    if type(gpu) == "string" and (component.type(gpu) ~= "gpu" or
          (screen and component.type(screen) ~= "screen")) or gpu.type ~= "gpu"
              then
      return nil, "invalid gpu/screen"
    end
    if type(gpu) == "string" then gpu = component.proxy(gpu) end
    if screen then gpu.bind(screen) end
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
    local cx, cy = 1, 1
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

    --[[
    local function flushwb()
      while unicode.len(wb) > 0 do
        checkCursor()
        local ln = unicode.sub(wb, 1, w - cx + 1)
        if ec then
          gpu.set(cx, cy, ln)
          cx = cx + unicode.len(ln)
        end
        wb = unicode.sub(wb, unicode.len(ln) + 1)
      end
    end]]
    local function flushwb()
      while #wb > 0 do
        checkCursor()
        local ln = wb:sub(1, w - cx + 1)
        gpu.set(cx, cy, ln)
        wb = wb:sub(#ln + 1)
        cx = cx + #ln
      end
      checkCursor()
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
            cx, cy = 1, cy + 1
            checkCursor()
          elseif c == "\t" then
            wb = wb .. (" "):rep(max(1, (cx + 4) % 8))
          elseif c == "\27" then
            flushwb()
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
          p = {}
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

-- sandbox --

kio.dmesg("ksrc/sandbox.lua")

-- loadfile --

function _G.loadfile(file, mode, env)
  checkArg(1, file, "string")
  checkArg(2, mode, "string", "nil")
  checkArg(3, env, "table", "nil")
  local handle, err = io.open(file, "r")
  if not handle then
    return nil, err
  end
  local data = handle:read("a")
  handle:close()
  return load(data, "="..file, mode or "bt", env or k.sb or _G)
end


do
  local sb = {}
  sb = table.copy(_G)
  sb._G = sb
  k.sb = sb
  local iomt = k.iomt
  k.iomt = nil
  k.hooks.sandbox(iomt)
end

-- load init from disk --

kio.dmesg("ksrc/loadinit.lua")

do
  local init = kargs.init or "/sbin/init.lua"
  local ok, err = loadfile(init, nil, k.sb)
  if not ok then
    kio.panic(err)
  end
  k.sched.spawn(ok, "[init]", 1)
end

if not k.sched.loop then
  kio.panic("SCHED LOOP MISSING")
end
k.sched.loop()

kio.panic("premature exit!")