-- vfs

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
    if mounts[path] then
      return nil, "there is already a filesystem mounted there"
    end
    mounts[path] = prx
    return true
  end
  
  function vfs.mounts()
    local ret = {}
    for k, v in pairs(mnt) do
      ret[v.address] = k
    end
    return ret
  end

  function vfs.umount()
  end
end
