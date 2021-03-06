-- sandbox hooks for wrapping kernel-level APIs more securely

do
  -- wrap rawset to respect blacklisted tables
  local old_rawset = rawset
  local blacklisted = {}
  function _G.rawset(tbl, key, val)
    checkArg(1, tbl, "table")
    if blacklisted[tbl] then
      -- trigger __newindex, throw error
      tbl[key] = val
    end
    old_rawset(tbl, key, val)
  end

  local function protect(tbl, name)
    local protected = setmetatable({}, {
      __index = tbl,
      __newindex = function()
        error((name or "lib") .. " is protected")
      end,
      __metatable = {}
    })
    blacklisted[protected] = true
    return protected
  end
  k.security.protect = protect

  -- snadbox hook for protecting certain sensitive APIs
  k.hooks.add("sandbox", function()
    k.sb.sha3 = protect(k.sb.k.sha3)
    k.sb.sha2 = protect(k.sb.k.sha2)
    k.sb.ec25519 = protect(k.sb.k.ec25519)
    k.sb.security = protect(k.sb.k.security)
    old_rawset(k.sb.security, "acl", protect(k.sb.k.security.acl))
    old_rawset(k.sb.security, "users", protect(k.sb.k.security.users))
  end)
end
