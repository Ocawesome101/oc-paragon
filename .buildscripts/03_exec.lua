-- exec module selection

local function select_exec()
  local add = ls("ksrc/exec")
  local prg = p()

  for k,v in pairs(add) do
    log(prg, "Adding exec module:", v)
    if #CONFIG.modules.exec == 0 then
      table.insert(CONFIG.modules.exec, v)
    else
      for kk, vv in pairs(CONFIG.modules.exec) do
        print(v,vv)
        if v ~= vv then
          table.insert(CONFIG.modules.exec, v)
          goto cont
        end
      end
    end
    ::cont::
  end
end

table.insert(build, select_exec)
