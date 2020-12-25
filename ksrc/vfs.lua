-- vfs

kio.dmesg(kio.loglevels.INFO, "ksrc/vfs.lua")

-- TODO: mount system is currently pretty basic.
local vfs = {}
do
  local mnt = {}

  --[[ expected procedure:
     1. use vfs.resolve to resolve a filepath to a proxy and a path on the proxy
     2. operate on the proxy
     the vfs api does not provide all available filesystem functions; see
     'src/fsapi.lua' for an api that does.
     note that while running a kernel without the fsapi module, you'll need to
     assign it as an initrd module for most of the system to function.  As such,
     fsapi is included by default. ]]

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
  -- vfs.resolve(path:string): table, string or nil, string
  --   Tries to resolve a file path to a filesystem proxy.
  function vfs.resolve(path)
    checkArg(1, path, "string")
    kio.dmesg(kio.loglevels.DEBUG, "vfs: resolve "..path)
    if path == "/" then
      if mnt["/"] then
        return mnt["/"], ""
      else
        return nil, "root filesystem not mounted"
      end
    end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    local segs = segments(path)
    for i=#segs, 1, -1 do
      local retpath = "/" .. table.concat(segs, "/", i, #segs)
      local try = "/" .. table.concat(segs, "/", 1, i)
      if mnt[try] then
        return mnt[try], retpath
      end
    end
    if path:sub(1,1)=="/" then
      return vfs.resolve("/"), path
    end
    kio.dmesg(kio.loglevels.DEBUG, "no such file: ".. path)
    return kio.error("FILE_NOT_FOUND")
  end

  -- vfs.mount(prx:table, path:string): boolean or nil, string
  --   Tries to mount the provided proxy at the provided file path.
  function vfs.mount(prx, path)
    checkArg(1, prx, "table")
    checkArg(2, path, "string")
    if not k.security.acl.hasPermission(k.security.users.user(), "MOUNT_FS") then
      return nil, "permission denied"
    end
    path = "/" .. table.concat(segments(path), "/")
    if mnt[path] then
      return nil, "there is already a filesystem mounted there"
    end
    if path ~= "/" then
      local node, spath = vfs.resolve(path)
      node:makeDirectory(spath)
    end
    mnt[path] = prx
    return true
  end
  
  -- vfs.mounts(): table
  --   Return a table with keys addresses and values paths of all mounted filesystems.
  function vfs.mounts()
    local ret = {}
    for k, v in pairs(mnt) do
      ret[v.address] = {
        path = k,
        type = v.fstype
      }
    end
    return ret
  end

  -- vfs.umount(path:string): boolean or nil, string
  --   Tries to unmount the proxy at the provided path.
  function vfs.umount(path)
    checkArg(1, path, "string")
    if not k.security.acl.hasPermission(k.security.users.user(), "MOUNT_FS") then
      return nil, "permission denied"
    end
    path = "/" .. table.concat(segments(path), "/")
    if not mnt[path] then
      return nil, "no such device"
    end
    mnt[path] = nil
    return true
  end

  -- vfs.stat(file:string): table or nil, string
  --   Tries to get information about a file or directory.
  function vfs.stat(file)
    checkArg(1, file, "string")
    local node, path = vfs.resolve(file)
    if not node then
      return nil, path
    end
    return node:stat(path)
  end
end
