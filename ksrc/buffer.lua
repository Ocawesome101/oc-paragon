-- simple buffer implementation --

do
  local buf = {}
  function buf.new(stream, mode)
    local new = {
      stream = stream,
      mode = {},
      tty = false, -- if true, then returned stream is not buffered
      rbuf = "",
      wbuf = "",
      closed = false,
      bufsize = 512
    }
    return setmetatable(new, {__index = buf})
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

  function buf:write(dat)
    checkArg(1, dat, "string")
    if #self.wbuf + dat > self.bufsize then
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
      local reqN = n + math.min(0, self.bufsize - n)
      repeat
        local dat = self.stream:read(reqN)
        if not dat then reqN = 0
         else reqN = reqN - #dat
              self.rbuf = self.rbuf .. dat
        end
      until reqN <= 0
    end
    local ret = self.rbuf:sub(1, n)
    self.rbuf = self.rbuf:sub(n + 1)
    return ret
  end

  kio.buffer = buf
end
