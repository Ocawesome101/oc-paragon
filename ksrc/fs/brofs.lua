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

  function temp:spaceUsed()
    return math.huge
  end

  function temp:spaceTotal()
    return self.dev.getCapacity()
  end

  function temp:isReadOnly()
    return true
  end

  function temp:open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string", "nil")
    file = strip(file)
    if self.ftable[file] then
    end
  end

  function drv.create(prx, label) -- takes an unmanaged drive (or a partition / file wrapper) and returns a BROFS interface
    kio.dmesg(3, "reading BROFS file table")
    local ftbl = ""
    ftbl = readSectors(prx, 1, 2)
    return setmetatable({dev = prx, ftable = ftable, label = label or (prx.getLabel and prx.getLabel()) or "BROFS"}, {__index = temp})
  end

  kdrv.fs.brofs = drv
end
