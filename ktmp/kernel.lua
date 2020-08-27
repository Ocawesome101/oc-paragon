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
  built   = "2020/08/26",
  builder = "ocawesome101@archlinux"
}

-- kernel i/o

kio = {}

kargs.loglevel = tonumber(kargs.loglevel) or 0

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
  PANIC   = 4
}

kio.levels = {
  [0] = "DEBUG",
  "INFO",
  "WARNING",
  "ERROR",
  "PANIC"
}

-- template stream
local _pipe = {}
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
  gpu.fill(1, 1, w, h, " ")
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
  if level >= kargs.loglevel then
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
    return t:gsub("/", "")
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
    if self.ftable[file] then
      local new = {
        ptr = 0,
        file = self.ftable[file]
      }
      local n = hn + 1
      hn = n
      self.handles[n] = new
      return n
    else
      return kio.error("FILE_NOT_FOUND")
    end
  end

  function temp:read(h, n)
    checkArg(1, h, "number")
    checkArg(2, n, "number")
    if not self.handles(h) then
      return nil, "bad file descriptor"
    end
    h = self.handles[h]
    if h.ptr >= h.file.size then
      return nil
    end
    if h.ptr + n >= h.file.size then
      n = h.file.size - h.ptr
    end
    local approx = readSectors(self.dev, h.file.start + h.ptr // 512, h.file.start + h.ptr // 512 + math.ceil(n + 512))
    local t = (h.ptr - h.ptr // 512 * 512)
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

  function temp:list()
    local files = {}
    for k, v in pairs(self.ftable) do
      table.insert(files, v)
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
    local inpat = string.rep(".", 32)
    for seg in ftbl:gmatch(inpat) do
      local start, size, prealloc, flags, _, fname = string.unpack(inpack, seg)
      if flags == 0 then
        break
      end
      -- file size is stored in approximate sectors but we need the exact count
      local last = prx.readSector(size)
      last = last:gsub("\0", "")
      local xsize = size * 512 - last
      local ent = {
        start = start,
        size = xsize,
        sect = size
        -- NOTE: prealloc is not used as the generated interface is read-only
      }
      ftable[fname] = ent
    end
    return setmetatable({dev = prx, ftable = ftable, label = label or (prx.getLabel and prx.getLabel()) or "BROFS"}, {__index = temp})
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
  
  function drv.create(prx)
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

  -- expected procedure:
  -- 1. use vfs.resolve to resolve a filepath to a proxy and a path on the proxy
  -- 2. operate on the proxy
  -- the vfs api does not provide all available filesystem functions. see
  -- 'misc/fsapi.lua' for an api that does.
  -- note that while running a kernel without the fsapi module, you'll need to
  -- either assign it as an initrd module or set 'security.uspace_vfs=1' in the
  -- kernel command line to allow userspace to access the vfs api (not
  -- recommended!).

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
  function vfs.resolve(path)
    checkArg(1, path, "string")
    local segs = segments(path)
    for i=#segs, 1, -1 do
      local retpath = "/" .. table.concat(segs, "/", i, #segs)
      local try = "/" .. table.concat(segs, "/", 1, i)
      if mnt[try] then
        return mnt[try], retpath
      end
    end
    return kio.error("FILE_NOT_FOUND")
  end

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
  
  function vfs.mounts()
    local ret = {}
    for k, v in pairs(mnt) do
      ret[v.address] = k
    end
    return ret
  end

  function vfs.umount(path)
    checkArg(1, path, "string")
    path = "/" .. table.concat(segments(path), "/")
    if not mns[path] then
      return nil, "no such device"
    end
    mns[path] = nil
    return true
  end
end

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

-- kernel api

kio.dmesg(kio.loglevels.INFO, "ksrc/kapi.lua")
k = {}
k.args    = kargs
k.io      = kio
k.info    = _KINFO
k.process = sched
k.drv     = kdrv

-- Paragon eXecutable parsing?

kio.dmesg(kio.loglevels.INFO, "ksrc/exec/px.lua")


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
  local fs = kargs.root or (computer.getBootAddress and computer.getBootAddress()) or kio.panic("neither root=? nor computer.getBootAddress present")

  local pspec, addr, pn = fs:match("(.+)%((.+),(%d+)%)")
  addr = addr or fs:gsub("[^%w%-]+", "")
  if not component.type(fs) then
    kio.panic("invalid rootfs specification " .. fs .. " (got " .. addr .. ")")
  end
  if component.type(addr) == "drive" then -- unmanaged, read partition table as specified
    if not pspec then
      kio.dmesg(kio.loglevels.WARNING, "no partitioning scheme specified!")
      kio.dmesg(kio.loglevels.WARNING, "defaulting to full drive as filesystem!")
    end
    if not kdrv.fs[pspec] then
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
      local handle = temp.open("pinitfs.img", "r")
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
    kio.panic("invalid rootfs specification:\n  component is not 'drive' or 'filesystem'")
  end
end

while true do computer.pullSignal() end
