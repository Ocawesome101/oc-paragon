# buffer.lua

Slightly broken buffer API.

  - `buffer.new(stream:table, mode:string): table` - create buffered stream from `stream` with mode `mode`.
    - `file:read(fmt)` - analogous to standard Lua.
    - `file:lines(fmt)` - analogous to standard Lua.  Broken.
    - `file:seek(...)` - analogous to standard Lua.
    - `file:write(...)` - analogous to standard Lua.
    - `file:flush()` - flush file buffer
    - `file:setvbuf(mode)` - set buffer mode
    - `file:close()` - analogous to standard Lua.
