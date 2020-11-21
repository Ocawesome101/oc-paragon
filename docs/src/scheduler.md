# scheduler.lua

The scheduler.  Hopefully priority-based.  Supports signals, deadlines, processes, and to an extent ownership.

  - `k.sched.spawn(func:function, name:string[, priority:number]): @process` - spawns a process, adding `func` to its threads.  Also returns the process.
  - `k.sched.getinfo([pid:number]): table or nil, string` - returns information about a process.  Highly dangerous, should not enter userspace under any circumstances.
  - `k.sched.signal(pid:number, sig:number): boolean or nil, string` - attempts to kill process `pid` with signal `sig`.  Only works if a) the current thread's owner owns the targeted thread or b) the current thread's owner is root.
  - `k.sched.kill` - see `k.sched.signal`.
  - `k.sched.newthread(func:function[, name:string]): boolean or nil, string` - adds a new thread to the current process.
  - `k.sched.loop()` - starts the scheduler loop.  Does not return.

This file also adds sandbox hooks to set up the userspace `process` API:

  - `process.spawn(func:function, name:string[, priority:number]): number` - spawns a process, adding `func` to its threads.  Returns the PID of the resulting process.
  - `process.info([pid:number]): table or nil, string` - returns information about a process.  Restricts available information, especially so when not returning information about the current process.
  - `process.current(): number` - returns the current process' PID.
  - `process.signal(pid:number, sig:number)` - see `k.sched.signal`.
  - `process.signals` - see `process.signals` under `process.md`.
  - `process.thread(func, name)` - see `k.sched.newthread`.
