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
