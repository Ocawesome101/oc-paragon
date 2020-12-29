-- basic event listeners

kio.dmesg(kio.loglevels.INFO, "ksrc/event.lua")

do
  local event = {}
  local listeners = {}
  local ps = computer.pullSignal

  function computer.pullSignal(timeout)
    checkArg(1, timeout, "number", "nil")
    local sig = table.pack(ps(timeout))
    if sig.n > 0 then
      for k, v in pairs(listeners) do
        if v.sig == sig[1] then
          local ok, ret = pcall(v.func, table.unpack(sig))
          if not ok and ret then
            kio.dmesg(kio.loglevels.ERROR, "event handler error: " .. ret)
          end
        end
      end
    end

    return table.unpack(sig)
  end

  function event.register(sig, func)
    checkArg(1, sig, "string")
    checkArg(2, func, "function")
    local n = 1
    while listeners[n] do
      n = n + 1
    end
    listeners[n] = {
      sig = sig,
      func = func
    }
    return n
  end

  function event.unregister(id)
    checkArg(1, id, "number")
    listeners[id] = nil
    return true
  end

  -- users may expect these to exist
  event.pull = computer.pullSignal
  event.push = computer.pushSignal
  k.evt = event
end
