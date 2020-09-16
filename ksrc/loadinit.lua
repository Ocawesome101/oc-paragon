-- load init from disk --

kio.dmesg("ksrc/loadinit.lua")

do
  local init = kargs.init or "/sbin/init.lua"
  local ok, err = loadfile(init, nil, k.sb)
  if not ok then
    kio.panic(err)
  end
  k.sched.spawn(init, "[init]", 1)
end
