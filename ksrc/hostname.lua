-- hostname --

do
  local h = {}
  function h.set(hn)
    checkArg(1, hn, "string")
    if k.security.users.user() ~= 0 then
      return kio.error("PERMISSION_DENIED")
    end
    k.hooks.hnset(hn)
    return true
  end

  function h.get()
    local names = {}
    k.hooks.hnget(names)
    return names
  end

  k.hooks.add("hnset", function(n)
    k.sched.getinfo().env.HOSTNAME = n
  end)

  k.hooks.add("hnget", function(t)
    t.standard = k.sched.getinfo().env.HOSTNAME or "localhost"
  end)

  k.hostname = h
end
