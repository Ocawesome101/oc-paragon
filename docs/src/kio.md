# kio.lua

Kernel I/O.

  - `k.io.errors = {FILE_NOT_FOUND, FILE_DIRECTORY, IO_ERROR, UNSUPPORTED_OPERATION, PERMISSION_DENIED, DEV_FULL, DEV_RO, BROKEN_PIPE}` - mappings of generic errors to specific messages, e.g. `DEV_FULL = "devices is full"`.
  - `k.io.loglevels = {DEBUG, INFO, WARNING, ERROR, PANIC}` - low-fidelity reflection of the Linux kernel loglevels.
  - `k.io.pipe(): table` - creates and returns a pipe stream.
  - `k.io.error(err:string): nil, string` - returns `nil, k.io.errors[err] or "generic error"`.
  - `k.io.dmesg([level:number, ]msg:string): boolean` - log `msg` to the console with loglevel `level`.  `level` defaults to `k.io.loglevels.INFO`.
  - `k.io.hide()` - hide kernel logs
  - `k.io.panic(msg:string)` - send the system into a panic state, using `msg` as the reason.  Prints a traceback to the console.
  - `k.io.buffer = {...}` - buffer API
