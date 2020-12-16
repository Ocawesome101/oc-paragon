-- various hooks called on different actions --

do
  local hooks = {}
  hooks.target = {}
  function hooks.add(k, v)
    checkArg(1, k, "string")
    checkArg(2, v, "function")
    hooks[k] = hooks[k] or setmetatable({}, {__call = function(self, ...) for k, v in ipairs(self) do v(...) end end})
    table.insert(hooks[k], v)
    return true
  end
  function hooks.call(k, ...)
    checkArg(1, k, "string")
    if hooks[k] then
      for k, v in ipairs(hooks[k]) do
        pcall(v, ...)
      end
    end
  end
  k.hooks = hooks
end

do
  -- some default hooks
  local function sbld(iomt)
    function k.sb.load(x, name, mode, env)
      return load(x, name, mode, env or k.sb)
    end
    setmetatable(k.sb.io, iomt)
    k.sb.k.vfs = table.copy(vfs)
    k.sb.k.iomt = nil
    k.sb.k.io.gpu = kio.gpu -- otherwise metatable weirdness happens
    k.sb.k.sb = nil -- just in case
  end
  k.hooks.add("sandbox", sbld)
end
