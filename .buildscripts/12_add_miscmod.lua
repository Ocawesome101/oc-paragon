-- put all misc mods into a file

local function misc_mod()
  local file = io.open("ktmp/misc.lua", "w")
  local prg = p()
  log(prg, "Adding misc modules")
  for k,v in pairs(CONFIG.modules.misc) do
    local ln = string.format("--#include \"ksrc/misc/%s\"", v)
    log(prg, ln)
    file:write(ln.."\n")
  end
  file:close()
end

table.insert(build, misc_mod)
