-- a scheduler! --

kio.dmesg(kio.loglevels.INFO, "ksrc/scheduler.lua")

do
  local procs = {}
  local s = {}
  local last, current = 0, 0
  -- TODO: proper process timeouts
  local timeout = tonumber(kargs["scheduler.timeout"]) or 0.5

  -- k.sched.spawn(func:function, name:string[, priority:number]): table
  --   Spawns a process, adding `func` to its threads.
  function s.spawn(func, name, priority)
    checkArg(1, func, "function")
    checkArg(2, name, "string")
    checkArg(3, priority, "number", "nil")
    last = last + 1
    local p = procs[current]
    local new = process.new {
      pid = last,
      parent = current,
      priority = priority or math.huge,
      env = p and table.copy(p.env) or {},
      stdin = p and p.io.stdin or {},
      stdout = p and p.io.stdout or {},
      stderr = p and p.io.stderr or {}
    }
    new:addThread(func)
    procs[new.pid] = new
    return new -- the userspace function will just return the PID
  end

  -- k.sched.getinfo(pid:number): table or nil, string
  --   Returns information about a process.
  -- XXX: This function is dangerous and should not sneak into userspace under
  -- XXX: any circumstances!
  function s.getinfo(pid)
    checkArg(1, pid, "number", "nil")
    pid = pid or current
    if not procs[pid] then
      return nil, "no such process"
    end
    return procs[pid]:info()
  end

  -- k.sched.signal(pid:number, sig:number): boolean or nil, string
  --   Attempts to kill process `pid` with signal `sig`.
  function s.signal(pid, sig)
    checkArg(1, pid, "number")
    checkArg(2, sig, "number")
    if not procs[pid] then
      return nil, "no such process"
    end
    local proc = procs[pid]
    if proc.owner == s.getinfo().owner or s.getinfo().owner == 0 then
      proc:signal(sig)
    else
      return kio.error("PERMISSION_DENIED")
    end
  end

  function s.loop()
    s.loop = nil
    local sig
    while #procs > 0 do
      sig = table.pack(computer.pullSignal(timeout))
      local run
      for pid, proc in pairs(procs) do
        if not proc.stopped then
          run[#run + 1] = proc
        end
      end
      table.sort(run, function(a, b)
        return a.priority < b.priority
      end)
    end
    kio.panic("All processes died!")
  end
  k.sched = s
end
