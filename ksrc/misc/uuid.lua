-- UUID module. UUID implementation copied from OpenOS

do
  k.uuid = {}

  function k.uuid.next()
    local sets = {4, 2, 2, 2, 6}
    local result = ""
    local pos = 0

    for _, set in ipairs(sets) do
      if #result > 0 then
        result = result .. "-"
      end
      for i=1, set, 1 do
        local byte = math.random(0, 255)
        if pos == 6 then
          byte = bit32.bor(bit32.band(byte, 0x0F), 0x40)
        elseif pos == 8 then
          byte = bit32.bor(bit32.band(byte, 0x3F), 0x80)
        end
        result = string.format("%s%02x", result, byte)
        pos = pos + 1
      end
    end

    return result
  end
end
