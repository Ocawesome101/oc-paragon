-- utils

do
  function table.copy(tbl)
    local seen = {}
    local function copy(t)
      local ret = {}
      for k, v in pairs(t) do
        if type(v) == "table" then
          if not seen[v] then
            seen[v] = true
            ret[k] = copy(v)
          end
        else
          ret[k] = v
        end
      end
      return ret
    end
    return copy(tbl)
  end
end
