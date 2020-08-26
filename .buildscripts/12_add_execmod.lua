-- put all misc mods into a file

local function exec_mod()
  local file = io.open("ktmp/exec.lua", "w")
  local prg = p()
  log(prg, "Adding exec format modules")
  for k,v in pairs(CONFIG.modules.misc) do
    local ln = string.format("--#include \"ksrc/exec/%s\"", v)
    log(prg, ln)
    file:write(ln.."\n")
  end
  file:close()
end

table.insert(build, exec_mod)
