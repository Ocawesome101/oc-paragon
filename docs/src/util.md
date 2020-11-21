# util.lua

Provides generic utility functions.

  - `table.copy(t:table): t` - returns a deep copy of `t`.  Deep copy implementation from https://lua-users.org/wiki/CopyTable - my implementation was apparently incompetent.
  - `collectgarbage()` - basic reimplementation of the standard Lua `collectgarbage` function.  Forces garbage collection and pushes any caught signals back into the queue in order so that they may be processed.
  - `string.hex(str:string): string` - turns a string into its hexadecimal representation e.g. `text` becomes `74657874`.
