-- access control lists....ish. --
-- these allow more granular control over what permissions certain users have

do
  local acl = {}
  acl.upasswd = {}

  local perms = {
    KILL_PROCESS = 1,
    FILE_ACCESS = 2,
    MOUNT_FS = 4,
    KILL_NOT_OWNED = 8,
    WRITE_NOT_OWNED = 16,
    RESTRICTED_API = 32,
    NO_SUDO_PASSWORD = 512
  }
  function acl.hasPermission(uid, pms)
    checkArg(1, uid, "number", "nil")
    checkArg(2, pms, "number", "string")
    uid = uid or k.security.users.user()
    pms = perms[pms] or pms
    if type(pms) == "string" then
      return nil, "no such permission: "..pms
    end
    local udat = acl.upasswd[uid] or (uid==0 and {permissions=1023})
    return uid == 0 or not (udat.permissions & pms) == 0
  end

  -- TODO: implement ability to give permissions to specific processes
  -- regardless of their owner

  k.security.acl = acl
end
