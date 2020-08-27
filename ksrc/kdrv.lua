-- kernel drivers

kio.dmesg(kio.loglevels.INFO, "ksrc/kdrv.lua")

kdrv = {}

kdrv.fs = {}
kdrv.tty = {}
kdrv.net = {}

--#include "ktmp/drivers.lua"
