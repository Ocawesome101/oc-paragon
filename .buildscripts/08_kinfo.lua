-- add kernel info to ktmp/kinfo.lua since preproc is being stupid

local function add()
  local prg = p()
  log(prg, "adding kernel info to ktmp/kinfo.lua")
  local hnh = io.popen("hostname", "r")
  local hostname = hnh:read("a"):gsub("\n", "")
  hnh:close()
  local file = io.open("ktmp/kinfo.lua", "w")
  file:write(string.format([[
_G._KINFO = {
  name    = "%s",
  version = "%s",
  built   = "%s",
  builder = "%s@%s"
}]], CONFIG.name or "Paragon", CONFIG.version or "<undefined>", os.date("%Y/%m/%d"), os.getenv("USER"), hostname))
end

table.insert(build, add)
