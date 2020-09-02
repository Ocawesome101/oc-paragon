-- load the fstab from the initfs and mount filesystems accordingly
-- from here on we work with the real rootfs, not the initfs

kio.dmesg(kio.loglevels.INFO, "ksrc/fstab.lua")

do
  local ifs, p = vfs.resolve("/fstab")
  if not ifs then
    kio.panic(p)
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
