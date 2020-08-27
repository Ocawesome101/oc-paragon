-- Paragon build system --

local getopt = require("lib.getopt")
local rawargs = {...}

local taken = {
  t = {
    takesarg = true,
    reqarg = true
  },
  target = {
    takesarg = true,
    reqarg = true
  }
}

-- parse arguments
local args, opts = getopt(rawargs, taken)

local target = opts.t or opts.target or "all"
local allmod = opts.d or opts.default or false

-- provides globals used in other scripts
_G.build = {}

function ls(dir)
  local hnd = io.popen("ls -1 " .. dir, "r")
  local f = {}
  for l in hnd:lines() do
    f[#f + 1] = l
  end
  hnd:close()
  return f
end

function rm(d)
  return os.execute("rm -rv "..d)
end

function mkdir(d)
  return os.execute("mkdir " .. d)
end

function log(...)
  print(table.concat(table.pack("\27[34m>>\27[39m", ...), " "))
end

for _, file in ipairs(ls(".buildscripts")) do
  log(file)
  dofile(".buildscripts/"..file)
end

if allmod then
  CONFIG.all_modules = true
end

if build[target] then
  build[target]()
else
  print("\27[91m>> Specified target was not found.\27[39m")
end
