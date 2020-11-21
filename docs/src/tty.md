# tty.lua

The VT100 terminal driver.  Supports standard 8-color, 16-color, 256-color, and 24-bit color modes.  I will not detail the VT100 specification here.

  - `k.vt.new(gpu:string or table[, screen:string]): @stream` - takes a GPU and (optionally) screen address, and returns a buffered stream suitable for use as standard IO.
