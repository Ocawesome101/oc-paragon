-- kernel drivers

kio.dmesg(kio.loglevels.INFO, "ksrc/kdrv.lua")

local kdrv = {}

kdrv.fs = {}
kdrv.tty = {}
kdrv.net = {}

--#include "ktmp/drivers.lua"
