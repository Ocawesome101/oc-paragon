-- load modules in order from initfs/mod*.lua

-- basic loadfile implementation
function loadfile(file)
  checkArg(1, file, "string")
  local node, path = vfs.resolve(file)
  if not node then
    return nil, path
  end
  local handle, err = node:open(path, "r")
  if not handle then
    return nil, err
  end
  local data = ""
  repeat
    local chunk, err = node:read(handle, math.huge)
    if not chunk and err then
      node:close(handle)
      return nil, err
    end
    data = data .. (chunk or "")
  until not chunk
  node:close(handle)
  return load(data, "=" .. file, "bt", _G)
end

do
  -- FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME
  local rootfs = select(2, xpcall(assert, kio.panic, vfs.resolve, "/"))
  local files = rootfs:list("/")
  table.sort(files)
  for i=1, #files, 1 do
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
