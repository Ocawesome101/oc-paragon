-- managed filesystem "driver"

do
  local drv = {}
  drv.name = "managed filesystem driver"
  drv.authors = {"Ocawesome101"}
  drv.license = {"GPLv3"}

  local default = {}
  setmetatable(default, {
    __index = function(_, k)
      default[k] = function(self, ...)
        if self.dev[k] then
          --local args={...}
          --for i=1,#args,1 do args[i]=tostring(args[i])end
          --kio.dmesg(kio.loglevels.PANIC, "INVOKE::"..k..":"..table.concat(args,","))
          return self.dev[k](...)
        else
          error((string.format("attempt to call field '%s' (a nil value)", k)))
        end
      end
      return default[k]
    end
  })
  
  function default:stat(file)
    if not self.dev.exists(file) then
      return nil, file .. ": file not found"
    end
    return {
      permissions = self:isReadOnly() and 365 or 511,
      isDirectory = self:isDirectory(file),
      owner       = -1,
      group       = -1,
      lastModified= self:lastModified(file),
      size        = self:size(file),
    }
  end
  
  function drv.create(prx)
    checkArg(1, prx, "table", "string")
    if type(prx) == "string" then prx = component.proxy(prx) end
    return setmetatable({dev = prx,
                         fstype = "managed",
                         address = prx.address
                       }, {__index = default})
  end

  kdrv.fs.managed = drv
end
