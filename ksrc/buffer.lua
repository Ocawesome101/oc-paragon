-- simple buffer implementation --

kio.dmesg(kio.loglevels.INFO, "ksrc/buffer.lua")

do
  local buf = {}
  local mt = {
    __index = buf,
    __metatable = "file"
  }

  function buf.new(stream, mode)
    checkArg(1, stream, "table")
    checkArg(2, mode, "string")
    local new = {
      stream = stream,
      mode = {},
      tty = false, -- if true, then returned stream is not buffered
      rbuf = "",
      wbuf = "",
      closed = false,
      bufsize = 512
    }
    for c in mode:gmatch(".") do
      new.mode[c] = true
    end
    return setmetatable(new, mt)
  end

  function buf:read(fmt)
    checkArg(1, fmt, "number", "string", "nil")
    fmt = fmt or "l"
    if type(fmt) == "string" then
      fmt = fmt:gsub("%*", "")
    end
    if fmt == "a" then
      return self:readNum(math.huge)
    elseif fmt == "l" then
      local ln = ""
      repeat
        local c = self:readNum(1)
        if c and c ~= "\n" then ln = ln .. c end
      until c == "\n" or not c
      return ln
    elseif fmt == "L" then
      local ln = ""
      repeat
        local c = self:readNum(1)
        if c then ln = ln .. c end
      until c == "\n" or not c
      return ln
    elseif type(fmt) == "number" then
      return self:readNum(fmt)
    else
      error("bad argument #1: invalid format")
    end
  end

  function buf:write(...)
    local args = table.pack(...)
    for i=1, args.n, 1 do
      checkArg(i, dat, "string", "number")
    end
    local dat = table.concat(args)
    self.wbuf = self.wbuf .. dat
    if #self.wbuf > self.bufsize then
      local wrt = self.wbuf
      self.wbuf = ""
      self.stream:write(wrt)
    end
  end

  function buf:flush()
    self.stream:write(self.wbuf)
    self.wbuf = ""
    return true
  end

  function buf:close()
    self:flush()
    self.closed = true
  end

  function buf:readNum(n)
    checkArg(1, n, "number")
    if #self.rbuf < n then
      local reqN = n ~= math.huge and n + math.min(0, self.bufsize - n) or n
      repeat
        local dat = self.stream:read(reqN)
        if not dat then reqN = 0
         else reqN = reqN - #dat
              self.rbuf = self.rbuf .. dat
        end
      until reqN <= 0
    end
    if n == math.huge then n = #self.rbuf end
    local ret = self.rbuf:sub(1, n)
    self.rbuf = self.rbuf:sub(n + 1)
    return ret
  end

  kio.buffer = buf
end
