-- network modules

local function select_net()
  local prg = p()
  io.write(prg .. " Enable network drivers? [Y/n] ")
  local inp = io.read():gsub("\n", "")
  if inp:lower() == "n" then
    log(prg, "Skipping network drivers")
    return
  end
  local nets = ls("ksrc/net")
  log(prg, "Select network drivers")
  local sel = menu(nets)

  for k, v in pairs(sel) do
    log(prg, "Adding network driver:", v)
    table.insert(CONFIG.modules.net, v)
  end
end

table.insert(build, select_net)
