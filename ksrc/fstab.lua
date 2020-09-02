-- load the fstab from the initfs and mount filesystems accordingly
-- from here on we work with the real rootfs, not the initfs

kio.dmesg(kio.loglevels.INFO, "ksrc/fstab.lua")

do
  local ifs, p = vfs.resolve("/fstab")
  if not ifs then
    kio.dmesg(kio.loglevels.DEBUG, "using args.root instead of initfs")
    kargs.root = kargs.root or computer.getBootAddress()
    if kargs.root then
      local pspec, addr, n = kargs.root:match("(.-)%(([%w%-]+),(%d+)%)")
      addr = addr or kargs.root
      pspec = pspec or "managed"
      if not k.drv.fs[pspec] then
        k.panic("invalid root partition spec: " .. pspec)
      end
      -- TODO TODO TODO TODO TODO: properly handle unmanaged drives
      local prx = k.drv.fs[pspec].create(addr, n)
      if not prx or prx.type ~= "filesystem" then
        k.panic("invalid root filesystem specification!")
      end
      vfs.umount("/")
      vfs.mount(prx, "/")
      ifs, p = prx, "/etc/fstab"
    end
  end
  local handle = ifs:open(p)
  local data = ""
  repeat
    local chunk = ifs:read(handle, math.huge)
    data = data .. (chunk or "")
  until not chunk
  ifs:close(handle)
  for line in data:gmatch("[^\n]+") do
    local partspec, path, fsspec, mode = line:match("(.-)%s+(.-)%s+(.-)%s+(.-)")
  end
end
::cont::
