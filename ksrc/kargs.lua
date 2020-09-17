-- parse kernel arguments

local cmdline = table.concat(table.pack(...), " ") -- ex. "init=/bin/sh loglevel=3 quiet"
local kargs = {}

for word in cmdline:gmatch("[^%s]+") do
  local k, v = word:match("(.-)=(.+)")
  k, v = k or word, v or true
  kargs[k] = v
end
