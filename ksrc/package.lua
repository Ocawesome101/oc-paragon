-- package library --

kio.dmesg("ksrc/package.lua")

k.hooks.add("sandbox", function()
  local package = {}
  k.sb.package = package
  local loading = {}
  local loaded = {
    _G = k.sb,
    os = k.sb.os,
    io = k.sb.io,
    math = k.sb.math,
    table = k.sb.table,
    bit32 = k.sb.bit32,
    string = k.sb.string,
    package = k.sb.package,
    process = k.sb.process,
    computer = k.sb.computer,
    component = k.sb.component,
    coroutine = k.sb.coroutine,
    filesystem = k.sb.fs
  }
  k.sb.fs = nil
  k.sb.process = nil
  k.sb.computer = nil
  k.sb.component = nil
  package.loaded = loaded

  package.path = "/lib/?.lua;/lib/lib?.lua;/lib/?/init.lua"

  function package.searchpath(name, path, sep, rep)
    checkArg(1, name, "string")
    checkArg(2, path, "string")
    checkArg(3, sep, "string", "nil")
    checkArg(4, rep, "string", "nil")
    sep = "%" .. (sep or ".")
    rep = rep or "/"
    local searched = {}
    name = name:gsub(sep, rep)
    for search in path:gmatch("[^;]+") do
      search = search:gsub("%?", name)
      if k.vfs.stat(search) then
        return search
      end
      searched[#searched + 1] = search
    end
    return nil, searched
  end

  function package.delay(lib, file)
    local mt = {
      __index = function(tbl, key)
        setmetatable(lib, nil)
        setmetatable(lib.internal or {}, nil)
        dofile(file)
        return tbl[key]
      end
    }
    if lib.internal then
      setmetatable(lib.internal, mt)
    end
    setmetatable(lib, mt)
  end

  function k.sb.require(module)
    checkArg(1, module, "string")
    if loaded[module] ~= nil then
      return loaded[module]
    elseif not loading[module] then
      local library, status, step

      step, library, status = "not found", package.searchpath(module, package.path)

      if library then
        step, library, status = "loadfile failed", loadfile(library)
      end

      if library then
        loading[module] = true
        step, library, status = "load failed", pcall(library, module)
        loading[module] = false
      end

      assert(library, string.format("module '%s' %s:\n%s", module, step, status))
      loaded[module] = status
      return status
    else
      error("already loading: " .. module .. "\n" .. debug.traceback(), 2)
    end
  end
end)
