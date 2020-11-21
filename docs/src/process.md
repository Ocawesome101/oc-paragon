# process.lua

Provides the `process` object used in the scheduler, as well as available signals.

  - `process.signals = {SIGHUP=1, SIGINT=2, SIGKILL=9, SIGTERM=15, SIGCONT=18, SIGSTOP=19}` - subset of standard UNIX process signals.
  - `process.new(args:table): @process` - create a new process.  `args` is used for internal undocumented purposes.

`process` object methods:
  - `process:resume(...): boolean` - resume all threads in the process.  Trims dead threads, and marks the process for removal if no threads remain.
  - `process:addThread(func:function[, name:string]): boolean` - add a thread to the process.
  - `process:info(): table` - returns a table of process information:
     ```lua
     {
       io=...,
       env=...,
       name=...,
       owner=...,
       started=...,
       runtime=...,
       threads=...,
       deadline=...,
       sighandlers=...,
       stdin=...,
       stdout=...,
       stderr=...
     }
     ```
  - `process:handle(sig:number): boolean or nil, string` - handles signal `sig` according to an internal signal handler.  Unless the process's PID is `1` (that is, the process is the init process), `SIGKILL` will always kill the process.
  - `process:kill(...)` - see `process:handle`
  - `process:stdin([file:table]): table` - if `file` is provided and is valid, set the process's standard inout to `file`.  Always returns the current standard input.
  - `process:stdout([file:table]): table`, `process:stderr([file:table]): table` - like `process:stdin()`, but operating on the standard output and standard erro streams respectively.
