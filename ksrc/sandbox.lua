-- sandbox --

kio.dmesg("ksrc/sandbox.lua")

--#include "ksrc/loadfile.lua"

do
  local sb = table.copy(_G)
  sb._G = sb
  k.sb = sb
  local iomt = k.iomt
  k.iomt = nil
  k.hooks.sandbox(iomt)
  function sb.package.loaded.computer.shutdown(rb)
    k.hooks.shutdown()
    computer.shutdown(rb)
  end
end
