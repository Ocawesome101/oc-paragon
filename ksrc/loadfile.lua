-- loadfile --

function _G.loadfile(file, mode, env)
  checkArg(1, file, "string")
  checkArg(2, mode, "string", "nil")
  checkArg(3, env, "table", "nil")
  local handle, err = io.open(file, "r")
  if not handle then
    return nil, err
  end
  local data = handle:read("a")
  handle:close()
  return load(data, "="..file, mode or "bt", env or k.sb or _G)
end

function _G.dofile(file)
  checkArg(1, file, "string")
  return assert(loadfile(file))()  
end
