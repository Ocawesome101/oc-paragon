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
          return self.dev[k](...)
        else
          error((string.format("attempt to call field '%s' (a nil value)", k)))
        end
      end
      return default[k]
    end
  })
  
  function default:stat(file)
    return {
      permissions = self:isReadOnly() and 292 or 438,
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
    return setmetatable({dev = prx}, {__index = default})
  end

  kdrv.fs.managed = drv
end
