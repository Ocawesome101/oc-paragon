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
      local n = (i - 1) * 32
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
