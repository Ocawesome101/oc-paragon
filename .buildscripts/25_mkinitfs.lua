-- generate an initfs

local function gen()
  local prg = p()
  local pat = "<I2I2I2I1I1c24"
  log(prg, "Generating initfs")
  local files = ls("initfs")
  local out = io.open("ktmp/pinitfs.img", "w")
  local ftbl = ""
  local flags = 1
  local start = 3
  out:write((string.rep("\0", 1024)))
  for _, file in pairs(files) do
    log(prg, "Add file", file)
    local h = io.open("initfs/"..file, "r")
    local data = h:read("a")
    out:write(data)
    h:close()
    local ftent = string.pack(pat, start, math.ceil(#data / 512), math.ceil(#data / 512), flags, 0xFF, file)
    if #ftent > 32 then
      error("INVALID FILE TABLE ENTRY LENGTH: "..#ftent)
    end
    start = start + math.ceil(#data / 512)
    ftbl = ftbl .. ftent
  end
  out:seek("set")
  out:write(ftbl)
  out:close()
end

table.insert(build, gen)
