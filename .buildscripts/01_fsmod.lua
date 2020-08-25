-- fs module selection

local function select_fs()
  local fses = ls("ksrc/fs")
  log("(1/5) Select filesystem drivers")
  local mods = menu(fses)

  for k,v in pairs(mods) do
    log("Adding filesystem driver:", v)
    for kk, vv in pairs(CONFIG.modules.fs) do
      if v ~= vv then
        table.insert(CONFIG.modules.fs, v)
        goto cont
      end
    end
    ::cont::
  end
end

table.insert(build, select_fs)
