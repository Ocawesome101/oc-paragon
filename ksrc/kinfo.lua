_G._KINFO = {
  name    = "@[{CONFIG.name or 'Paragon'}]",
  version = "@[{CONFIG.version or 'undefined'}]",
  built   = "@[{os.date('%Y.%m.%d')}]",
  builder = "@[{os.getenv('USER') or 'unknown'}]@@[{os.getenv('HOSTNAME') or 'unknown'}]"
}
