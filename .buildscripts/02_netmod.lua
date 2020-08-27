-- network modules

local function select_net()
  local prg = p()
  if not CONFIG.all_modules then
    io.write(prg .. " Enable network drivers? [Y/n] ")
    local inp = io.read():gsub("\n", "")
    if inp:lower() == "n" then
      log(prg, "Skipping network drivers")
      return
    end
  end
  local nets = ls("ksrc/net")
  log(prg, "Select network drivers")
  local sel
  if CONFIG.all_modules then
    sel = nets
  else
    sel = menu(nets)
  end

  for k, v in pairs(sel) do
    log(prg, "Adding network driver:", v)
    table.insert(CONFIG.modules.net, v)
  end
end

table.insert(build, select_net)
