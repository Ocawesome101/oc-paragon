-- a scheduler! --

kio.dmesg(kio.loglevels.INFO, "ksrc/scheduler.lua")

do
  local procs = {}
  local s = {}
  local last, current = 0, 0

  -- k.sched.spawn(func:function, name:string): table
  --   Spawns a process, adding `func` to its threads.
  function s.spawn(func, name)
    checkArg(1, func, "function")
    checkArg(2, name, "string")
    last = last + 1
    local p = procs[current]
    local new = process.new {
      pid = last,
      parent = current,
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
    checkArg(1, pid, "string")
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
  end

  function s.loop()
    s.loop = nil
  end
  k.sched = s
end
