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
    __newindex = function(self, key, value)
      local info = k.sched.getinfo()
      if key == "stdin" then
        info.io.stdin = value
      elseif key == "stdout" then
        info.io.stdout = value
      elseif key == "stderr" then
        info.io.stderr = value
      else
        rawset(self, key, value)
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
      if err == path then
        return nil, file..": no such file or directory"
      end
      return nil, err
    end
    local stream = streamify(node, handle)
    return kio.buffer.new(stream, mode)
  end

  local function open(f, m)
    if type(f) == "string" then
      return io.open(f, m)
    else
      return f
    end
  end

  function io.input(file)
    local info = k.sched.getinfo()
    return info:input(open(file, "r"))
  end

  function io.output(file)
    local info = k.sched.getinfo()
    return info:output(open(file, "w"))
  end

  function io.read(...)
    return io.input():read(...)
  end

  function io.write(...)
    return io.output():write(...)
  end

  function io.lines(file, ...)
    if not file then
      return io.input():lines(...)
    end
    return io.open(file, "r"):lines(...)
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
