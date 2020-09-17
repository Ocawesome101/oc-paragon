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
