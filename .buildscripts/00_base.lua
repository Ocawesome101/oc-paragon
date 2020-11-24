CONFIG = {
  version = os.getenv("KERNEL_VERSION") or "undefined",
  modules = {
    fs = {
      "brofs.lua"
    },
    net = {
    },
    exec = {
    },
    misc = {
      "event.lua",
      "sha3.lua"
    }
  }
}

local tui = require("lib.tui")

local function prompt(msg)
  local ret = ""
  while not ret:match("%d") do
    io.write(msg)
    ret = io.read()
  end
  return ret
end

local n = 1
function p()
  n = n + 1
  return string.format("(%d/%d)", n - 1, #build)
end

--[[function menu(opts)
  for i=1, #opts, 1 do
    print(string.format("%d. %s", i, opts[i]))
  end
  local range = prompt("Enter a selection (e.g. 1 or 1,2,3 or 1,7,2): ")
  local sel = {}
  for n in range:gmatch("[^,]+") do
    if tonumber(n) then
      table.insert(sel, opts[tonumber(n)])
    end
  end
  return sel
end]]

function menu(opts)
  local items = {}
  for i=1, #opts, 1 do
    items[i] = {text = opts[i], selectable = true}
  end
  local sel = tui.menu(items)
  local ret = {}
  for k, v in pairs(sel) do
    table.insert(ret, opts[k])
  end
  io.write("\27[0m\27[2J\27[1;1H")
  return ret
end

rm("ktmp")
mkdir("ktmp")
rm("build")
mkdir("build")
