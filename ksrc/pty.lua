-- PTYs: open terminal streams --
-- PTY here doesn't mean quite the same thing as it does in most Unix-likes

kio.dmesg("ksrc/pty.lua")

do
  local opened = {}
  
  local pty = {}

  local dinfo = computer.getDeviceInfo()

  local gpus, screens = {}, {}

  for k,v in component.list() do
    if v == "gpu" then
      gpus[#gpus+1] = {addr=k,res=tonumber(dinfo[k].capacity),bound=false}
    elseif v == "screen" then
      screens[#screens+1] = {addr=k,res=tonumber(dinfo[k].capacity),bound=false}
    end
  end

  local function get(t, r)
    local ret = {}
    for i=1, #t, 1 do
      local o = t[i]
      if not o.bound then
        ret[o.res] = ret[o.res] or o
      end
    end
    return ret[r] or ret[8000] or ret[2000] or ret[800]
  end

  local function open_pty()
    local gpu = get(gpus)
    if gpu then
      local screen = get(screens, gpu.res)
      if screen then
        local new = k.vt.new(gpu.addr, screen.addr)
        gpu.bound = screen.addr
        screen.bound = gpu.addr
        local close = new.close
        function new:close()
          close(new)
          gpu.bound = false
          screen.bound = false
        end
        return new
      end
    end
    return nil
  end

  function pty.streams()
    return function()
      local new = open_pty()
      if new then
        return kio.buffer.new(new, "rw")
      end
    end
  end

  k.pty = pty
end
