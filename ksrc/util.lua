-- utils

kio.dmesg(kio.loglevels.INFO, "ksrc/util.lua")
do
  -- from https://lua-users.org/wiki/CopyTable because apparently my implementation is incompetent
  local function deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
      if copies[orig] then
        copy = copies[orig]
      else
        copy = {}
        copies[orig] = copy
        for orig_key, orig_value in next, orig, nil do
          copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
        end
        setmetatable(copy, deepcopy(getmetatable(orig), copies))
      end
    else -- number, string, boolean, etc
      copy = orig
    end
    return copy
  end
  function table.copy(t)
    checkArg(1, t, "table")
    return deepcopy(t)
  end
end
