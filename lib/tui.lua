-- tui --

local term = require("lib.term")

local tui = {}

local function pad(s, w)
  return s .. (" "):rep(w - #s)
end

local function fill(tx, ty, w, h)
  local ln = term.color(pad(" ", w), nil, term.colors.bg.white)
  for y=ty, ty+h, 1 do
    term.cursor(tx, y)
    io.write(ln)
  end
end

local w, h = term.getSize()
local function draw(items, title, hlt, sel)
  fill(2, 2, w - 4, h - 4)
  term.cursor(3, 3)
  io.write(term.color(title, term.colors.fg.black, term.colors.bg.white))
  for i=1, #items, 1 do
    local text = pad(items[i].text, w - 10)
    if items[i].selectable then
      if sel[i] then
        text = "[x] " .. text
      else
        text = "[ ] " .. text
      end
    else
      text = "--> " .. text
    end
    if hlt == i then
      text = term.color(text, term.colors.fg.bright.white, term.colors.bg.red)
    else
      text = term.color(text, term.colors.fg.black, term.colors.bg.white)
    end
    term.cursor(3, i + 4)
    io.write(text)
  end
end

function tui.menu(items, title)
  io.write(term.color("", nil, term.colors.bg.blue))
  term.clear()
  title = title or "Menu"
  local sel = 1
  local selected = {}
  while true do
    draw(items, title, sel, selected)
    local key = term.getKey()
    if key == "up" then
      if sel > 1 then sel = sel - 1 end
    elseif key == "down" then
      if sel < #items then sel = sel + 1 end
    elseif key == " " or key == "\13" then
      if items[sel].selectable then
        selected[sel] = not selected[sel]
      else
        selected[sel] = true
        return selected
      end
    elseif key == "left" or key == "right" then
      return selected
    end
  end
end

return tui
