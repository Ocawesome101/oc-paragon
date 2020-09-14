-- sandbox --

kio.dmesg("ksrc/sandbox.lua")

--#include "ksrc/loadfile.lua"

do
  local sb = {}
  sb = table.copy(_G)
  sb._G = sb
  function sb.load(x,n,m,e)return load(x,n,m,e or sb)end
  setmetatable(sb.io, k.iomt)
  k.iomt = nil
end
