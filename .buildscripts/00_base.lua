CONFIG = {
  version = "0.0.1",
  modules = {
    fs = {
      "brofs.lua"
    },
    net = {
    },
    misc = {
    }
  }
}

local function prompt(msg)
  local ret = ""
  while not ret:match("%d") do
    io.write(msg)
    ret = io.read()
  end
  return ret
end

function menu(opts)
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
end

rm("ktmp")
mkdir("ktmp")
