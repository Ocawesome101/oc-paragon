-- a scheduler! --

kio.dmesg(kio.loglevels.INFO, "ksrc/scheduler.lua")

do
  local procs = {}
  local s = {}
  local last, current = 0, 0

  -- k.sched.spawn(func:function, name:string): table
  --   Spawns a process, adding `func` to its threads.
  function s.spawn(func, name)
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
    procs[new.pid] = new
    return new -- the userspace function will just return the PID
  end

  -- k.sched.getinfo(pid:number): table or nil, string
  --   Returns information about a process.
  function s.getinfo(pid)
  end

  k.sched = s
end
