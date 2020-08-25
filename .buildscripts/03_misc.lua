-- misc module selection

local function select_mods()
  local mods = ls("ksrc/misc")
  local prg = p()
  log(prg, "Select misc modules")
  local mods = menu(mods)

  for k,v in pairs(mods) do
    log("Adding misc module:", v)
    for kk, vv in pairs(CONFIG.modules.misc) do
      if v ~= vv then
        table.insert(CONFIG.modules.misc, v)
        goto cont
      end
    end
    ::cont::
  end
end

table.insert(build, select_mods)
