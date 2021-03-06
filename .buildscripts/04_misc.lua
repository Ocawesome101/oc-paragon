-- misc module selection

local function select_mods()
  local mods = ls("ksrc/misc")
  local prg = p()
  log(prg, "Select misc modules")
  local add
  if CONFIG.all_modules then
    add = mods
  else
    add = menu(mods)
  end

  for k,v in pairs(add) do
    log(prg, "Adding misc module:", v)
    if #CONFIG.modules.misc == 0 then
      table.insert(CONFIG.modules.misc, v)
    else
      for kk, vv in pairs(CONFIG.modules.misc) do
        if v ~= vv then
          table.insert(CONFIG.modules.misc, v)
          goto cont
        end
      end
    end
    ::cont::
  end
end

table.insert(build, select_mods)
