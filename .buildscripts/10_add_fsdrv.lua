-- put all drivers into a file

local function fs_drv()
  local file = io.open("ktmp/drivers.lua", "w")
  for k,v in pairs(CONFIG.modules.fs) do
    local ln = string.format("--#include \"ksrc/fs/%s\"", v)
    log(ln)
    file:write(ln.."\n")
  end
  file:close()
end

table.insert(build, fs_drv)
