-- network modules

local function select_net()
  io.write("(2/5) Enable network drivers? [Y/n] ")
  local inp = io.read():gsub("\n", "")
  if inp:lower() == "n" then
    log("(2/5) Skipping network drivers")
    return
  end
  local nets = ls("ksrc/net")
  log("(2/5) Select network drivers")
  local sel = menu(nets)

  for k, v in pairs(sel) do
    log("Adding network driver:", v)
    table.insert(CONFIG.modules.net, v)
  end
end

table.insert(build, select_net)
