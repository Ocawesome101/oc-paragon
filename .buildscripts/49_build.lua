-- build the whole thing

local function mk()
  local prg = p()
  log(prg, "Building Paragon kernel")
  local preproc = require("lib.preproc")
  preproc("ksrc/init.lua", "build/kernel.lua")
  log(prg, "Done.")
end

table.insert(build, mk)
