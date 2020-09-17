-- kernel api

kio.dmesg(kio.loglevels.INFO, "ksrc/kapi.lua")
_G.k = {}
k.args    = kargs
k.io      = kio
k.info    = _KINFO
k.process = sched
k.drv     = kdrv
