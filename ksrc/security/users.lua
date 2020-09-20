-- users --

kio.dmesg("ksrc/security/users.lua")

do
  -- NOTE: processes cannot, and I repeat, CANNOT authenticate themselves as
  -- NOTE: a user other than their current one. This simplifies certain things.
  local users = {}
  local upasswd = {}
  
  -- users.prime(passwd:table): boolean or nil, string
  --   Prime the 'users' API with data from a passwd file, usually /etc/passwd.
  function users.prime(passwd)
    checkArg(1, passwd, "table")
    if not passwd[0] and passwd[0].hash and passwd[0].name and passwd[0].home
                                                                            then
      return nil, "no root password definition"
    end
    users.prime = nil
    k.sb.k.security.users.prime = nil
    upasswd = passwd
    return true
  end

  local msgs = {
    "no such user",
    "invalid credentials",
    "permission denied"
  }

  function users.checkAuth(uid, passwd, _)
    checkArg(1, uid, "number")
    checkArg(2, passwd, "string")
    if not upasswd[uid] then
      return nil, _ and 1 or msgs[1]
    end
    if string.hex(k.sha3.sha512(passwd)) == upasswd[uid].hash then
      return true
    else
      return nil, _ and 2 or msgs[2]
    end
  end

  function users.spawnAs(uid, passwd, func, name)
    checkArg(1, uid, "number")
    checkArg(2, passwd, "string")
    checkArg(3, func, "function")
    checkArg(4, name, "string")
    local ok, code = users.checkAuth(uid, passwd, true)
    if not ok then
      return nil, msgs[code <= 1 and code or 3]
    end
    local pid = k.sched.spawn(function()
      local inf = k.sched.getinfo()
      inf.env.HOME = upasswd[uid].home
      inf.env.SHELL = upasswd[uid].shell
      func()
    end, name, nil, uid)
    repeat
      coroutine.yield()
    until not k.sched.getinfo(pid)
    return true
  end

  function users.user()
    return (k.sched.getinfo() or {}).owner or 0
  end

  k.security.users = users
end

-- add sandbox hooks
do
  k.hooks.add("sandbox", function()
    -- raw component restrictions
    sb.component = setmetatable({}, {__index = function(_,m)
      if k.security.users.user() ~= 0 then
        error(select(2, kio.error("PERMISSION_DENIED")))
      end
      return component[m]
    end, __metatable = {}})
  end)
end
