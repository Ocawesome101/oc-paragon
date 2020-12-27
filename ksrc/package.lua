-- package library --


k.hooks.add("sandbox", function()
  kio.dmesg("ksrc/package.lua")
  local package = {}
  k.sb.package = package
  local loading = {}
  local loaded = {
    _G = k.sb,
    os = k.sb.os,
    io = k.sb.io,
    sha2 = k.sb.sha2,
    sha3 = k.sb.sha3,
    math = k.sb.math,
    pipe = {create = k.io.pipe},
    event = table.copy(k.evt),
    table = k.sb.table,
    users = k.sb.security.users,
    bit32 = k.sb.bit32,
    vt100 = table.copy(k.vt),
    string = k.sb.string,
    buffer = table.copy(k.io.buffer),
    package = k.sb.package,
    process = k.sb.process,
    ec25519 = k.sb.ec25519,
    internet = table.copy(k.drv.net.internet or {}),
    security = k.sb.security,
    hostname = table.copy(k.hostname),
    computer = k.sb.computer,
    component = k.sb.component,
    coroutine = k.sb.coroutine,
    filesystem = k.sb.fs
  }
  k.sb.k = nil
  k.sb.fs = nil
  k.sb.vfs = nil
  k.sb.sha2 = nil
  k.sb.sha3 = nil
  k.sb.bit32 = nil
  k.sb.process = nil
  k.sb.ec25519 = nil
  k.sb.security = nil
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
      if vfs.stat(search) then
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
        k.sb.dofile(file)
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
