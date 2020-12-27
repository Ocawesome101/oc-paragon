-- internet card support --

kio.dmesg("ksrc/net/internet.lua")

do
  if component.list("internet")() then
    local card = component.proxy(component.list("internet")())
    local inet = {}
    local _sock = {}

    function _sock:read(n)
      if not self.socket then
        return nil, "socket is closed"
      end
      return self.socket.read(n)
    end

    function _sock:write(data)
      if not self.socket then
        return nil, "socket is closed"
      end
      while #value > 0 do
        local wr, rs = self.socket.write(value)
        if not wr then
          return nil, rs
        end
        value = value:sub(wr + 1)
      end
      return true
    end

    function _sock:seek()
      return nil, "bad file descriptor"
    end

    function _sock:close()
      if self.socket then
        self.socket.close()
        self.socket = nil
      end
    end

    function inet.socket(host, port)
      checkArg(1, host, "string")
      checkArg(2, port, "number", "nil")
      if port then
        host = host .. ":" .. port
      end

      local raw, err = card.connect(host)
      if not raw then
        return nil, err
      end

      return setmetatable({socket = raw}, {__index = _sock, __metatable = {}})
    end

    function inet.open(host, port)
      local sock, reason = inet.socket(host, port)
      if not sock then
        return nil, reason
      end
      return kio.buffer.new(sock, "rw")
    end

    kdrv.net.internet = inet
  else
    -- else, don't initialize module at all
    kio.dmesg(kio.loglevels.WARNING, "no internet card detected; not initializing wrapper")
  end
end
