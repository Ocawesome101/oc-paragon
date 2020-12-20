-- load init from disk --

kio.dmesg("ksrc/loadinit.lua")

local function pre_run()
  if k.io.gpu then
    local vts = k.vt.new(k.io.gpu, k.io.screen)
    io.input(vts)
    io.output(vts)
    k.sched.getinfo():stderr(vts)
  end
end

do
  if computer.freeMemory() < 8192 then
    kio.dmesg("NOTE: init may not load; low memory")
  end
  local init = kargs.init or "/sbin/init.lua"
  local ok, err = loadfile(init, nil, k.sb)
  if not ok then
    kio.panic(err)
  end
  k.sched.spawn(function()pre_run()ok(k)end, "[init]", 1)
end

k.sched.loop()
