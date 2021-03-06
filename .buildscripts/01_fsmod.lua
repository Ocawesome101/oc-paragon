-- fs module selection

local function select_fs()
  local fses = ls("ksrc/fs")
  local prg = p()
  log(prg, "Select filesystem drivers")
  local mods
  if CONFIG.all_modules then
    mods = fses
  else
    mods = menu(fses)
  end

  for k,v in pairs(mods) do
    log(prg, "Adding filesystem driver:", v)
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
