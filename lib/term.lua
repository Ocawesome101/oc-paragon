-- library for interfacing with a VT100 terminal from standard Lua

local term = {}

local sub = {
  ["A"] = "up",
  ["B"] = "down",
  ["C"] = "right",
  ["D"] = "left",
  ["1;5A"] = "ctrl-up",
  ["1;5B"] = "ctrl-down",
  ["1;5C"] = "ctrl-right",
  ["1;5D"] = "ctrl-left",
  ["1;3A"] = "alt-up",
  ["1;3B"] = "alt-down",
  ["1;3C"] = "alt-right",
  ["1;3D"] = "alt-left",
  ["5~"] = "pgup",
  ["6~"] = "pgdown",
  ["H"] = "home",
  ["F"] = "end"
}

function term.getKey()
  os.execute("stty raw -echo")
  local key = io.read(1)
  if key == "\27" then
    local temp = io.read(1)
    if temp == "[" then
      local esc = ""
      repeat
        local char = io.read(1)
        esc = esc .. char
      until char:match("[^0-9;]")
      key = sub[esc] or esc
    else
      key = "<ESC>"..temp
    end
  end
  os.execute("stty sane")
  return key
end

local function cpos()
  os.execute("stty raw -echo")
  io.write("\27[6n")
  local resp = ""
  repeat
    local c = io.read(1)
    resp = resp .. c
  until c == "R"
  os.execute("stty sane")
  local y, x = resp:match("\27%[(%d+);(%d+)R")
  return tonumber(x), tonumber(y)
end

function term.getSize()
  io.write("\27[9999;9999H")
  return cpos()
end

function term.cursor(x, y)
  if x and y then
    io.write(string.format("\27[%d;%dH", y, x))
  else
    return cpos()
  end
end

function term.clear()
  io.write("\27[2J")
end

term.colors = {
  fg = {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    purple = 35,
    cyan = 36,
    white = 37,
    bright = {}
  },
  bg = {
    bright = {}
  }
}

-- populate the rest of the table
for k, v in pairs(term.colors.fg) do
  if type(v) == "number" then
    term.colors.bg[k] = v + 10
    term.colors.fg.bright[k] = v + 60
    term.colors.bg.bright[k] = v + 70
  end
end

function term.color(text, fgcol, bgcol)
  return string.format("\27[%d;%dm%s", fgcol or 39, bgcol or 49, text)
end

return term
