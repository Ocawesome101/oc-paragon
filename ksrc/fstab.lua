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
