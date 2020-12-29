-- power management-ish; specifically sleep-mode --

do
  k.hooks.add("sandbox", function()
    k.sb.package.loaded.pwman = {
      suspend = function()
        if k.security.users.user() ~= 0 then
          return nil, "only root can do that"
        end
        k.hooks.sleep()
      end
    }
  end)
end
