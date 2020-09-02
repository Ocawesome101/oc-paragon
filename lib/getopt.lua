-- the Monolith shell.getopt implementation --

local function getopt(args, argdefs)
  local parsed_args, parsed_opts, done_opts, i = {}, {}, false, 1
  local function get(opt)
    local def = argdefs[opt] or {takesarg = false, reqarg = false}
    if def.takesarg then
      local try = args[i + 1]
      if def.reqarg and not try then
        error("getopt: missing argument for option " .. opt, 0)
      end
      parsed_opts[opt] = try or parsed_opts[opt] or true
      i = i + 1
    else
      parsed_opts[opt] = true
    end
  end
  while i <= #args do
    local parse = args[i]
    if parse == "-" or done_opts then
      table.insert(parsed_args, opt)
    elseif parse == "--" then
      done_opts = true
    else
      local short = false
      if parse:sub(1,2) == "--" then
        parse = parse:sub(3)
      elseif parse:sub(1,1) == "-" then
        parse = parse:sub(2)
        short = true
      end
      if short and #parse > 1 then
        local o = parse:sub(1,1)
        parsed_opts[o] = (parse:sub(2)) or parsed_opts[o] or true
      else
        get(parse)
      end
    end
    i = i + 1
  end
  return parsed_args, parsed_opts
end

return getopt
