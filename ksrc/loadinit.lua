-- load init from disk --

kio.dmesg("ksrc/loadinit.lua")

do
  if computer.freeMemory() < 8192 then
    kio.dmesg("NOTE: init may not load; low memory")
  end
  local init = kargs.init or "/sbin/init.lua"
  local ok, err = loadfile(init, nil, k.sb)
  if not ok then
    kio.panic(err)
  end
  k.sched.spawn(function()ok(k)end, "[init]", 1)
end

k.sched.loop()
