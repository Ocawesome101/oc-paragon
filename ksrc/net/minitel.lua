-- Minitel

kio.dmesg(kio.loglevels.INFO, "ksrc/net/minitel.lua")

do
  -- this is mostly a straight-up port of the OpenOS service
  -- slightly modified to work with the Paragon kernel's feature set
  -- and re-indented to match the rest of the code
  -- also all comments are completely stripped

  local component = component
  local computer = computer
  local event = k.evt

  local cfg = {
    debug = not not kargs["mtel.debug"],
    port = tonumber(kargs["mtel.modem-port"]) or 4096,
    retry = tonumber(kargs["mtel.retry"]) or 10,
    retrycount = tonumber(kargs["mtel.retry-count"]) or 10,
    route = not not kargs["mtel.route"]
  }

  cfg.sroutes = {}
  local rcache = setmetatable({}, {__index = cfg.sroutes})
  local pcache = {}
  cfg.rctime = 15
  cfg.pctime = 15
  local pqueue = {}

  local log
  local function concat(...)
    local args = table.pack(...)
    local ret = ""
    for i=1, args.n, 1 do
      ret = ret .. tostring(args[i]) .. " "
    end
    return ret
  end
  local function dprint(...)
    if cfg.debug then
      log = log or io.open("/mtel-dbg.log", "a") or io.open("/mtel-dbg.log", "w")
      if log then
        log:write(concat(...).."\n")
        log:flush()
      end
    end
  end
  k.hooks.add("shutdown", function()
    if log then log:close() end
  end)

  local hostname = k.hostname.get()
  k.hooks.add("hnset", function(name)
    hostname = name or computer.address():sub(1,4)
  end)

  k.hooks.add("hnget", function(names)
    names.minitel = hostname
  end)

  local modems = {}
  for a, t in component.list("modem", true) do
    modems[#modems + 1] = component.proxy(a)
    modems[#modems].open(cfg.port)
  end

  for a, t in component.list("tunnel", true) do
    modems[#modems + 1] = component.proxy(a)
  end
  
  local function genPacketID()
    local id = ""
    for i=1, 16, 1 do
      id = id .. string.char(math.random(32, 126))
    end
    return id
  end

  local function sendPacket(packetID,packetType,dest,sender,vPort,data,repeatingFrom)
    if rcache[dest] then
      dprint("Cached", rcache[dest][1],"send",rcache[dest][2],cfg.port,packetID,packetType,dest,sender,vPort,data)
      if component.type(rcache[dest][1]) == "modem" then
        component.invoke(rcache[dest][1],"send",rcache[dest][2],cfg.port,packetID,packetType,dest,sender,vPort,data)
      elseif component.type(rcache[dest][1]) == "tunnel" then
        component.invoke(rcache[dest][1],"send",packetID,packetType,dest,sender,vPort,data)
      end
    else
      dprint("Not cached", cfg.port,packetID,packetType,dest,sender,vPort,data)
      for k,v in pairs(modems) do
        -- do not send message back to the wired or linked modem it came from
        -- the check for tunnels is for short circuiting `v.isWireless()`, which does not exist for tunnels
        if v.address ~= repeatingFrom or (v.type ~= "tunnel" and v.isWireless()) then
          if v.type == "modem" then
            v.broadcast(cfg.port,packetID,packetType,dest,sender,vPort,data)
          elseif v.type == "tunnel" then
            v.send(packetID,packetType,dest,sender,vPort,data)
          end
        end
      end
    end
  end

  local function pruneCache()
    for k,v in pairs(rcache) do
      dprint(k,v[3],computer.uptime())
      if v[3] < computer.uptime() then
        rcache[k] = nil
        dprint("pruned "..k.." from routing cache")
      end
    end
    for k,v in pairs(pcache) do
      if v < computer.uptime() then
        pcache[k] = nil
        dprint("pruned "..k.." from packet cache")
      end
    end
  end

  local function checkPCache(packetID)
    dprint(packetID)
    for k, v in pairs(pcache) do
      dprint(k)
      if k == packetID then
        return true
      end
    end
    return false
  end

  local function processPacket(_,localModem,from,pport,_,packetID,packetType,dest,sender,vPort,data)
    pruneCache()
    if pport == cfg.port or pport == 0 then -- for linked cards
      dprint(cfg.port,vPort,packetType,dest)
      if checkPCache(packetID) then return end
      if dest == hostname then
        if packetType == 1 then
          sendPacket(genPacketID(),2,sender,hostname,vPort,packetID)
        end
        if packetType == 2 then
          dprint("Dropping "..data.." from queue")
          pqueue[data] = nil
          computer.pushSignal("net_ack",data)
        end
        if packetType ~= 2 then
          computer.pushSignal("net_msg",sender,vPort,data)
        end
      elseif dest:sub(1,1) == "~" then -- broadcasts start with ~
        computer.pushSignal("net_broadcast",sender,vPort,data)
      elseif cfg.route then -- repeat packets if route is enabled
        sendPacket(packetID,packetType,dest,sender,vPort,data,localModem)
      end
      if not rcache[sender] then -- add the sender to the rcache
        dprint("rcache: "..sender..":", localModem,from,computer.uptime())
        rcache[sender] = {localModem,from,computer.uptime()+cfg.rctime}
      end
      if not pcache[packetID] then -- add the packet ID to the pcache
        pcache[packetID] = computer.uptime()+cfg.pctime
      end
    end
  end

  event.register("modem_message", processPacket)

  local function queuePacket(_,ptype,to,vPort,data,npID)
    npID = npID or genPacketID()
    if to == hostname or to == "localhost" then
      computer.pushSignal("net_msg",to,vPort,data)
      computer.pushSignal("net_ack",npID)
      return
    end
    pqueue[npID] = {ptype,to,vPort,data,0,0}
    dprint(npID,table.unpack(pqueue[npID]))
  end

  event.register("net_send", queuePacket)

  local function packetPusher()
    for k,v in pairs(pqueue) do
      if v[5] < computer.uptime() then
        dprint(k,v[1],v[2],hostname,v[3],v[4])
        sendPacket(k,v[1],v[2],hostname,v[3],v[4])
        if v[1] ~= 1 or v[6] == cfg.retrycount then
          pqueue[k] = nil
        else
          pqueue[k][5]=computer.uptime()+cfg.retry
          pqueue[k][6]=pqueue[k][6]+1
        end
      end
    end
  end

  event.register("net_ack", dprint)

  local function ppthread()
    while true do
      packetPusher()
      coroutine.yield(0.5)
    end
  end

  k.hooks.add("uspace", function()
    k.sched.spawn(ppthread, "[kworker-mtel]")
  end)
end
