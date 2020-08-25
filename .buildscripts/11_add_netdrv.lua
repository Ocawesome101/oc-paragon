-- put all drivers into a file

local function net_drv()
  local file = io.open("ktmp/drivers.lua", "a")
  local prg = p()
  log(prg, "Adding network drivers")
  for k,v in pairs(CONFIG.modules.net) do
    local ln = string.format("--#include \"ksrc/net/%s\"", v)
    log(prg, ln)
    file:write(ln.."\n")
  end
  file:close()
end

table.insert(build, net_drv)
