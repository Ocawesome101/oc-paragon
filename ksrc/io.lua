-- buffered file I/O and misc other --

do
  local io = {}
  _G.io = io

  local vfs = vfs

  local iomt = {
    __index = function(self, k)
      local info = k.sched.getinfo()
      if k == "stdin" then
        return info:stdin()
      elseif k == "stdout" then
        return info:stdout()
      elseif k == "stderr" then
        return info:stderr()
      end
    end,
    __metatable = {}
  }
  setmetatable(io, iomt)

  local st = {}
  function st:read(n)
    return self.node:read(self.fd, n)
  end

  function st:write(d)
    return self.node:write(self.fd, d)
  end

  function st:close()
    return self.node:close(self.fd)
  end

  local function streamify(node, fd)
    local new = {
      node = node,
      fd = fd
    }
    return setmetatable(new, {__index = st})
  end
  
  -- io.open(file:string[, mode:string]): table or nil, string
  --   Returns a buffered file handle to 
  function io.open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string", "nil")
    local node, path = vfs.resolve(file)
    if not node then
      return nil, path
    end
    local handle, err = node:open(path, mode)
    if not handle then
      return nil, err
    end
    local stream = streamify(node, handle)
    return kio.buffer.new(stream, mode)
  end

  function io.input(file)
    local info = k.sched.getinfo()
    return info:stdin(file)
  end

  function io.output(file)
    local info = k.sched.getinfo()
    return info:stdout(file)
  end

  function io.read(...)
    return io.stdin:read(...)
  end

  function io.write(...)
    return io.stdout:write(...)
  end
end
