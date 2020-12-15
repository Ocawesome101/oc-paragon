-- simple filesystem API

kio.dmesg("src/fsapi.lua")

do
  -- for now, we'll just only provide userspace with this one
  k.hooks.add("sandbox", function()
    local vfs = k.sb.vfs
    local fs = {}

    fs.stat = vfs.stat
    fs.mount = vfs.mount
    fs.mounts = vfs.mounts
    fs.umount = vfs.umounts

    function fs.isReadOnly(file)
      checkArg(1, file, "string", "nil")
      local node, path = vfs.resolve(file or "/")
      if not node then
        return nil, path
      end
      return node:isReadOnly(path)
    end

    function fs.makeDirectory(path)
      checkArg(1, path, "string")
      local sdir, dend = path:match("(.+)/(.-)")
      sdir = sdir or "/"
      dend = dend~=""and dend or path
      local node, dir = vfs.resolve(sdir)
      if not node then
        return nil, dir
      end
      local ok, err = node:makeDirectory(dir.."/"..dend)
      if not ok and err then
        return nil, err
      end
      return true
    end

    function fs.remove(file)
      checkArg(1, file, "string")
      local node, path = vfs.resolve(file)
      if not node then
        return nil, path
      end
      return node:remove(path)
    end
  
    function fs.list(dir)
      checkArg(1, dir, "string")
      local node, path = vfs.resolve(dir)
      if not node then
        return nil, path
      end
      return node:list(path)
    end

    k.sb.fs = fs
  end)
end
