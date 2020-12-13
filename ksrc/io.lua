-- buffered file I/O and misc other --

kio.dmesg(kio.loglevels.INFO, "ksrc/io.lua")

do
  local io = {}
  _G.io = io

  local vfs = vfs

  local iomt = {
    __index = function(self, key)
      local info = k.sched.getinfo()
      if key == "stdin" then
        return info:stdin()
      elseif key == "stdout" then
        return info:stdout()
      elseif key == "stderr" then
        return info:stderr()
      end
    end,
    __metatable = {}
  }
  k.iomt = iomt
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
    return info:input(file)
  end

  function io.output(file)
    local info = k.sched.getinfo()
    return info:output(file)
  end

  function io.read(...)
    return io.input():read(...)
  end

  function io.write(...)
    return io.output():write(...)
  end

  k.hooks.add("sandbox", function()
    function k.sb.print(...)
      local args = table.pack(...)
      for i=1, args.n, 1 do
        args[i] = tostring(args[i])
      end
      io.stdout:write(table.concat(args, "\t") .. "\n")
      return true
    end
  end)
  --TODO: flesh out io, maybe in userspace?
end
