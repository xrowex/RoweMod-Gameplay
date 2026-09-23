--[[
    Multiplayer session: capture local skater â†’ mailbox â†’ bridge â†’ peers,
    apply remote packets onto ghost skaters (tricks/grinds + transform).

    Peers must share the same mapId. Until they do, gameplay sync is gated.
]]

for _,n in ipairs({"mp.avatar","mp.codec","mp.protocol","mp.interpolate"}) do package.loaded[n]=nil end
local protocol = require("mp.protocol")
local mailbox = require("mp.mailbox")
local capture = require("mp.capture")
local ghost = require("mp.ghost")
local mapinfo = require("mp.mapinfo")

local M = {}

local function log(msg)
    print("[RoweModMP] " .. tostring(msg))
end

local state = {
    active = false,
    cfg = nil,
    box = nil,
    ghosts = nil,
    propMap = nil,
    seq = 0,
    prevSnap = nil,
    lastTransformSent = 0,
    playerName = "skater",
    peerNames = {},
    peerMaps = {},
    peerHealth = {},
    localMapId = "unknown",
    sessionMapId = nil, -- host authority map when enabled
    isHost = false,
    notify = nil,
    mapsMatched = false,
    lastMismatchNotify = 0,
    pendingTravel = nil,
}

local function next_seq()
    state.seq = state.seq + 1
    return state.seq
end

local function send_line(line)
    if state.box then
        state.box:write_line(line)
    end
end

local function notify(msg)
    if state.notify then
        state.notify(msg)
    end
    log(msg)
end

-- Declared before refresh_local_map so a later map transition uses the local
-- helper rather than looking for a nonexistent global function.
local host_map_authority

local function refresh_local_map()
    local info = mapinfo.current()
    local id = info.id or "unknown"
    if id ~= state.localMapId then
        state.localMapId = id
        if state.ghosts then state.ghosts:clear() end
        if state.isHost then state.sessionMapId = id end
        if state.active and id ~= "unknown" then
            send_line(protocol.encode_map(next_seq(), id))
            send_line(protocol.encode_hello(next_seq(), state.playerName, id))
            -- A host changing maps must actively replace a joiner's earlier
            -- StartMenu session target. Waiting for the next joiner hello
            -- left an avoidable one-way render gate after loading a park.
            if state.isHost and host_map_authority() then
                send_line(protocol.encode_map_req(next_seq(), id))
            end
            log("local map -> " .. id)
            notify("map: " .. id)
        end
    end
    return id
end

local function require_same_map()
    local cfg = state.cfg or {}
    if cfg.requireSameMap == nil then
        return true
    end
    return not not cfg.requireSameMap
end

host_map_authority = function()
    local cfg = state.cfg or {}
    if cfg.hostMapAuthority == nil then
        return true
    end
    return not not cfg.hostMapAuthority
end

local function maps_in_sync()
    if state.travel and (state.travel.phase=="loading" or state.travel.phase=="failed" or state.travel.phase=="waiting") then return false end
    if not require_same_map() then
        return true
    end
    local target = state.sessionMapId or state.localMapId
    if not target or target == "" or target == "unknown" then
        return false
    end
    if not mapinfo.same(state.localMapId, target) then
        return false
    end
    -- If we know peers, all must match; if none yet, local==session is enough to send.
    -- Different-map peers are gated individually, not allowed to freeze everyone.
    return true
end

local function recompute_match()
    local matched = maps_in_sync()
    if matched ~= state.mapsMatched then
        state.mapsMatched = matched
        if matched then
            notify("map OK: " .. tostring(state.localMapId))
        else
            local peerList = {}
            for peerId, mapId in pairs(state.peerMaps) do
                peerList[#peerList + 1] = string.format("%s=%s", peerId, mapId)
            end
            notify(string.format(
                "map mismatch local=%s session=%s peers[%s]",
                tostring(state.localMapId),
                tostring(state.sessionMapId or "?"),
                table.concat(peerList, ",")
            ))
        end
    end
    return matched
end

local function peer_map_compatible(peerMap)
    if not require_same_map() then
        return true
    end
    local target = state.sessionMapId or state.localMapId
    return mapinfo.same(peerMap, target) and mapinfo.same(state.localMapId, target)
end

local function send_hello()
    refresh_local_map()
    send_line(protocol.encode_hello(next_seq(), state.playerName, state.localMapId))
    send_line(protocol.encode_map(next_seq(), state.localMapId))
end

local function scope_rail(railId)
    local mapId = state.localMapId or "unknown"
    railId = tostring(railId or "")
    if railId == "" then
        return mapId .. "#"
    end
    if railId:find("#", 1, true) then
        return railId
    end
    return mapId .. "#" .. railId
end

local function handle_map_req(msg)
    local want = mapinfo.normalize(msg.mapId or "")
    if want == "" or want == "unknown" then
        return
    end
    state.sessionMapId = want
    if state.cfg and state.cfg.autoTravelToHostMap then
        state.travel:request(want,state.localMapId,capture.local_pawn()~=nil)
        recompute_match()
        return
    end
    if mapinfo.same(state.localMapId, want) then
        send_line(protocol.encode_map_ack(next_seq(), state.localMapId, true))
        recompute_match()
        return
    end
    local auto = state.cfg and state.cfg.autoTravelToHostMap
    if auto or state.pendingTravel == want then
        state.pendingTravel = nil
        notify("traveling to " .. want)
        local ok, detail = mapinfo.travel(want)
        send_line(protocol.encode_map_ack(next_seq(), want, ok))
        log("travel " .. tostring(detail))
        if not ok then
            notify("travel failed: " .. tostring(detail))
        end
    else
        notify("host map=" .. want .. " â€” rowemod mp travel  (or enable autoTravelToHostMap)")
        send_line(protocol.encode_map_ack(next_seq(), state.localMapId, false))
    end
    recompute_match()
end

local function handle_packet(line, defaultPeer)
    local peerId = defaultPeer or "peer"
    local raw = line
    local at, rest = line:match("^@([^|]+)|(.*)$")
    if at then
        peerId = at
        raw = rest
    end
    local msg = protocol.decode(raw)
    if not msg then
        return
    end

    if msg.type == "hello" then
        if msg.ver ~= protocol.VERSION then return end
        local changed = state.peerNames[peerId] ~= msg.name or state.peerMaps[peerId] ~= msg.mapId
        state.peerNames[peerId] = msg.name or peerId
        local peerMap = mapinfo.normalize(msg.mapId or "unknown")
        state.peerMaps[peerId] = peerMap
        if state.isHost and host_map_authority() then
            state.sessionMapId = state.localMapId
            -- Tell joiner what map we are on.
            send_line(protocol.encode_map_req(next_seq(), state.localMapId))
        elseif not state.sessionMapId then
            state.sessionMapId = peerMap
        end
        recompute_match()
        if peer_map_compatible(peerMap) then
            state.ghosts:ensure(peerId, msg.name)
        else
            state.ghosts:remove(peerId)
        end
        if changed then log(string.format("hello from %s map=%s", tostring(msg.name), peerMap)) end
        -- Reply so they learn our map too.
        send_line(protocol.encode_map(next_seq(), state.localMapId))
        return
    end

    if msg.type == "map" then
        local peerMap = mapinfo.normalize(msg.mapId or "unknown")
        state.peerMaps[peerId] = peerMap
        recompute_match()
        if not peer_map_compatible(peerMap) then
            state.ghosts:remove(peerId)
        end
        return
    end

    if msg.type == "map_req" then
        if not state.isHost and (not state.cfg.online or state.bridgeJoined) then handle_map_req(msg) end
        return
    end

    if msg.type == "map_ack" then
        state.peerMaps[peerId] = mapinfo.normalize(msg.mapId or "unknown")
        recompute_match()
        return
    end

    if msg.type == "bye" then
        state.ghosts:remove(peerId)
        state.peerNames[peerId] = nil
        state.peerMaps[peerId] = nil
        state.peerHealth[peerId] = nil
        recompute_match()
        return
    end

    -- Gameplay packets only when maps agree (and peer is on our map).
    local peerMap = state.peerMaps[peerId]
    local health
    if msg.type == "frame" then
        health=state.peerHealth[peerId] or {received=0,applied=0}
        state.peerHealth[peerId]=health
        health.received=health.received+1
        health.lastFrame=os.time()
        health.reason=health.lastError or "waiting for introduction"
    end
    if require_same_map() then
        if not state.mapsMatched then
            if health then health.reason="waiting for local map" end
            return
        end
        if peerMap and not mapinfo.same(peerMap, state.localMapId) then
            if health then health.reason="peer on another map: "..tostring(peerMap) end
            return
        end
    end

    if msg.type == "frame" and peerMap and mapinfo.same(msg.mapId,state.localMapId) then
        local ok,applied=pcall(state.ghosts.apply_frame,state.ghosts,peerId,msg)
        if not ok then
            health.reason=tostring(applied):gsub("[\r\n]"," "):sub(1,512)
            if health.lastError~=health.reason then log("avatar "..peerId..": "..health.reason) end
            health.lastError=health.reason
        elseif applied then
            health.applied=health.applied+1;health.reason="visible";health.lastError=nil
        elseif not health.lastError then health.reason="waiting for newer pose" end
    elseif health and peerMap then
        health.reason="pose on another map: "..tostring(msg.mapId)
    end
end

-- Plain-file evidence includes gated/failed players, not just existing actors.
-- No engine object calls are needed to report a missing avatar.
local function report_visibility()
    if os.time()-(state.lastVisibilityReport or 0)<2 then return end
    state.lastVisibilityReport=os.time()
    local ids={};for peer in pairs(state.peerNames) do ids[peer]=true end
    for peer in pairs(state.peerHealth) do ids[peer]=true end
    local rows={M.status()}
    for peer in pairs(ids) do
        local h=state.peerHealth[peer] or {}
        rows[#rows+1]=string.format("peer=%s name=%s map=%s received=%d applied=%d age=%s status=%s",peer,
            tostring(state.peerNames[peer] or "?"):gsub("[\r\n]"," "),tostring(state.peerMaps[peer] or "?"),
            h.received or 0,h.applied or 0,h.lastFrame and tostring(os.time()-h.lastFrame) or "never",
            h.reason or "waiting for first pose")
    end
    local f=io.open(state.box.dir.."/visibility.txt","wb")
    if f then f:write(table.concat(rows,"\n"));f:close() end
    local function enc(value)
        return tostring(value or ""):gsub("[%%\t\r\n]",function(c) return string.format("%%%02X",c:byte()) end)
    end
    local health={"updated\t"..os.time(),"lobby\t"..tostring(state.bridgeLobby or "0")}
    for _,player in ipairs(M.players().players) do
        health[#health+1]=table.concat({"player",enc(player.id),enc(player.status),enc(player.map),
            enc(player.received),enc(player.applied),enc(player.detail)},"\t")
    end
    local path=state.box.dir.."/player_health.txt"
    f=io.open(path..".tmp","wb")
    if f then f:write(table.concat(health,"\n"));f:close();os.remove(path);os.rename(path..".tmp",path) end
end

function M.is_active()
    return state.active
end

function M.local_map()
    return state.localMapId
end

function M.maps_ok()
    return state.mapsMatched
end
function M.map_status()
    return state.travel and {phase=state.travel.phase,message=state.travel.message,target=state.travel.target} or {phase="idle"}
end
function M.players()
    local result={lobby=state.bridgeLobby or "0",players={}}
    if not state.active then return result end
    local ids={};for id in pairs(state.peerNames) do ids[id]=true end
    for id in pairs(state.peerHealth) do ids[id]=true end
    for id in pairs(ids) do
        local h=state.peerHealth[id] or {}
        local status="Waiting for poses"
        local slot=state.ghosts and state.ghosts.ghosts[id]
        if not state.mapsMatched then status="Loading map"
        elseif state.peerMaps[id] and not mapinfo.same(state.peerMaps[id],state.localMapId) then status="On another map"
        elseif h.lastFrame and os.time()-h.lastFrame>5 then status="Poses interrupted"
        elseif h.lastError or slot and slot.renderError then status="Avatar failed"
        elseif slot and slot.lastRendered and os.time()-slot.lastRendered>5 then status="Avatar not updating"
        elseif slot and (slot.renders or 0)>0 then status="Avatar active"
        elseif (h.applied or 0)>0 then status="Preparing avatar" end
        result.players[#result.players+1]={id=id,name=state.peerNames[id] or "Skater",map=state.peerMaps[id] or "unknown",
            status=status,received=h.received or 0,applied=h.applied or 0,detail=h.lastError or slot and slot.renderError or h.reason or "Waiting for first pose"}
    end
    table.sort(result.players,function(a,b) return a.id<b.id end)
    return result
end
function M.retry_map()
    if state.active and not state.isHost and state.travel and state.travel.target then
        state.travel:request(state.sessionMapId or state.travel.target,state.localMapId,capture.local_pawn()~=nil,true)
    end
end

function M.inspect(continuous)
    if continuous ~= nil then state.diagnostics = continuous end
    local rows = { M.status() }
    local function describe(label, actor)
        if not actor or not actor:IsValid() then
            rows[#rows + 1] = label .. "=none"
            return
        end
        local p = actor:K2_GetActorLocation()
        rows[#rows + 1] = string.format("%s=%s xyz=%.2f,%.2f,%.2f", label,
            actor:GetFullName(), p.X, p.Y, p.Z)
        local s = actor:GetActorScale3D()
        rows[#rows + 1] = string.format("%s scale=%.3f,%.3f,%.3f", label, s.X, s.Y, s.Z)
    end
    local helpers = require("UEHelpers")
    local pc = helpers.GetPlayerController()
    describe("local", capture.local_pawn())
    if pc and pc:IsValid() then describe("view", pc:GetViewTarget()) end
    if state.ghosts then
        rows[#rows+1]=string.format("work_ms capture=%.2f render=%.2f",state.captureMs or 0,state.ghosts.renderMs or 0)
        for peer, slot in pairs(state.ghosts.ghosts) do
            describe("ghost " .. peer, slot.actor)
            rows[#rows+1]="avatar "..peer.." parts="..#slot.parts.." frames="..tostring(slot.frames or 0).." renders="..tostring(slot.renders or 0).." shared_pose_parts="..tostring(slot.sharedParts or 0)
            if slot.last then
                rows[#rows + 1] = string.format("received %s xyz=%.2f,%.2f,%.2f", peer,
                    slot.last.x, slot.last.y, slot.last.z)
            end
        end
    end
    local report = table.concat(rows, "\n")
    log(report)
    if state.box then
        local f = io.open(state.box.dir .. "/diagnostics.txt", "wb")
        if f then f:write(report); f:close() end
    end
    return report
end

function M.avatar_census()
    require("mp.avatar").census(capture.local_pawn(), state.box.dir)
end

-- Explicit developer transport check: move the real source pawn, then let the
-- ordinary capture/UDP/ghost path replicate it. Never runs during normal play.
function M.test_move(dx, dy)
    local pawn = capture.local_pawn()
    if not pawn then return false end
    dx = math.max(-500, math.min(500, tonumber(dx) or 300))
    dy = math.max(-500, math.min(500, tonumber(dy) or 0))
    local p = pawn:K2_GetActorLocation()
    if dx==0 and dy==0 and state.ghosts then
        for _,slot in pairs(state.ghosts.ghosts) do
            if slot.last then
                p={X=slot.last.x+250,Y=slot.last.y,Z=slot.last.z+50}
                break
            end
        end
    end
    pawn:K2_SetActorLocation({ X = p.X + dx, Y = p.Y + dy, Z = p.Z }, false, {}, true)
    M.inspect(true)
    return true
end

function M.status()
    if not state.active then
        return "mp off"
    end
    local bridge = state.box and state.box:read_bridge_status() or "?"
    local connected = "?"
    pcall(function()
        local f = io.open(state.box.dir .. "/connected.txt", "rb")
        if f then
            connected = (f:read("*l") or "?"):gsub("%s+", "")
            f:close()
        end
    end)
    local peers = 0
    for _ in pairs(state.peerNames) do
        peers = peers + 1
    end
    return string.format(
        "mp on map=%s session=%s ok=%s peers=%d connected=%s bridge=%s",
        tostring(state.localMapId),
        tostring(state.sessionMapId or "?"),
        tostring(state.mapsMatched),
        peers,
        tostring(connected),
        tostring(bridge)
    )
end

function M.start(cfg, notify_fn)
    if state.active then
        M.stop()
    end
    cfg = cfg or {}
    state.cfg = cfg
    state.notify = notify_fn
    state.playerName = cfg.playerName or "skater"
    state.isHost = not not cfg.isHost
    state.propMap = capture.merge_prop_map(cfg.props)
    state.box = mailbox.open(cfg.mailboxDir)
    state.ghosts = ghost.create_manager(state.propMap)
    state.prevSnap = nil
    state.seq = os.time()*1000
    state.lastTransformSent = 0
    state.peerNames = {}
    state.peerMaps = {}
    state.peerHealth = {};state.lastVisibilityReport=nil
    state.mapsMatched = false
    state.pendingTravel = nil
    state.localMapId="unknown";state.sessionMapId=nil
    state.bridgeLobby=nil;state.bridgeJoined=false;state.lastRoleCheck=nil
    state.travel=require("mp.travel").new(function(want)
        state.ghosts:clear()
        notify("Loading host's park: "..want)
        return mapinfo.travel(want)
    end,function(actual,ok)
        send_line(protocol.encode_map_ack(next_seq(),actual,ok))
    end)
    state.active = true
    -- Render independently of packet capture/polling. Keep this on UE4SS's
    -- persistent native game-thread timer (the async handoff caused the crash).
    if not state.renderLoop then
        state.renderLoop = require("game_thread").loop(16,function()
            if state.active and state.ghosts then state.ghosts:render(os.clock()) end
        end)
    end
    refresh_local_map()
    if state.isHost or host_map_authority() and cfg.isHost ~= false and cfg.role == "host" then
        state.isHost = true
        state.sessionMapId = state.localMapId
    else
        state.sessionMapId = state.localMapId
    end
    state.box:write_status(string.format(
        "game_up name=%s map=%s host=%s",
        state.playerName,
        state.localMapId,
        tostring(state.isHost)
    ))
    pcall(function()
        local h=require("UEHelpers")
        h.GetKismetSystemLibrary():ExecuteConsoleCommand(h.GetWorld(),"Slate.RequireFocusForGamepadInput 1",h.GetPlayerController())
    end)
    send_hello()
    if state.isHost then
        send_line(protocol.encode_map_req(next_seq(), state.localMapId))
    end
    recompute_match()
    log("session started map=" .. state.localMapId .. " mailbox=" .. state.box.dir)
    notify("MP on map=" .. state.localMapId)
    M.inspect(false)
    return true
end

function M.stop(notify_fn)
    if state.active then
        send_line(protocol.encode_bye(next_seq()))
    end
    if state.ghosts then
        state.ghosts:clear()
    end
    state.active = false
    state.travel=nil
    if state.renderLoop and type(CancelDelayedAction)=="function" then
        CancelDelayedAction(state.renderLoop)
        state.renderLoop=nil
    end
    state.box = nil
    state.ghosts = nil
    state.prevSnap = nil
    state.peerNames = {}
    state.peerMaps = {}
    state.peerHealth = {}
    state.mapsMatched = false
    log("session stopped")
    local n = notify_fn or state.notify
    if n then
        n("MP off")
    end
end

--- Host (or anyone) asks peers to travel to mapId (default: local map).
function M.request_map(mapId)
    if not state.active then
        return false, "mp off"
    end
    mapId = mapinfo.normalize(mapId or state.localMapId)
    if not state.isHost then return false, "only the host can change the session map" end
    state.sessionMapId = mapId
    send_line(protocol.encode_map_req(next_seq(), mapId))
    notify("map req -> " .. mapId)
    recompute_match()
    return true, mapId
end

--- Travel local game to mapId, then announce.
function M.travel(mapId)
    mapId = mapinfo.normalize(mapId or state.sessionMapId or "")
    if mapId == "" or mapId == "unknown" then
        return false, "no map"
    end
    state.pendingTravel = mapId
    local ok, detail = mapinfo.travel(mapId)
    if ok then
        notify("traveling: " .. mapId)
    else
        notify("travel failed: " .. tostring(detail))
    end
    return ok, detail
end

function M.tick()
    if not state.active then
        return
    end

    -- Steam sessions can change role without restarting the game. The local
    -- companion is the authority for role; remote packets never change it.
    if state.cfg.online and os.time() ~= state.lastRoleCheck then
        state.lastRoleCheck = os.time()
        local bridge = state.box:read_bridge_status() or ""
        local role,lobby=bridge:match("^(%a+) transport=steam lobby=(%d+) peers=%d+")
        -- An empty/partial read is not a leave event. Preserve the last known
        -- host role and avatars until a complete companion status arrives.
        if role=="host" or role=="join" or role=="idle" then
            local isHost=role=="host"
            state.bridgeJoined=lobby~="0" and role=="join"
            if state.isHost ~= isHost or state.bridgeLobby~=lobby then
                state.bridgeLobby=lobby
                state.ghosts:clear();state.peerMaps={};state.peerNames={};state.peerHealth={}
                state.isHost = isHost
                state.sessionMapId = isHost and state.localMapId or nil
                if state.travel then state.travel.phase="idle";state.travel.target=nil;state.travel.queued=nil end
                if isHost then send_line(protocol.encode_map_req(next_seq(), state.localMapId)) end
            end
        end
    end

    refresh_local_map()
    if state.travel then state.travel:update(state.localMapId,capture.local_pawn()~=nil) end
    recompute_match()
    for id,s in pairs(state.ghosts.ghosts) do
        if os.time()-(s.lastSeen or os.time())>5 then state.ghosts:remove(id) end
    end

    local lines = state.box:poll_inbox(48)
    for _, line in ipairs(lines) do
        local ok, err = pcall(handle_packet, line, "peer")
        if not ok then
            log("handle err: " .. tostring(err))
        end
    end
    report_visibility()

    -- Outbound only when map gate open (still send hello/map via other paths).
    if require_same_map() and not state.mapsMatched then
        local now = os.clock()
        if (now - (state.lastMismatchNotify or 0)) > 5.0 then
            state.lastMismatchNotify = now
            -- lightweight reminder in log only
            log(M.status())
        end
        -- Keep announcing our map so peers can catch up.
        if (now - (state.lastTransformSent or 0)) > 2.0 then
            state.lastTransformSent = now
            send_line(protocol.encode_map(next_seq(), state.localMapId))
        end
        return
    end

    local pawn = capture.local_pawn()
    if not pawn then
        return
    end
    local now=os.clock()
    if now-state.lastTransformSent >= 1/20 then
        state.lastTransformSent=now
        local captureStarted=os.clock()
        local ok, frame=pcall(require("mp.avatar").capture,pawn)
        if ok then
            send_line(protocol.encode_frame(next_seq(),state.localMapId,frame))
        elseif os.time()~=(state.lastCaptureError or 0) then
            state.lastCaptureError=os.time()
            log("avatar capture: "..tostring(frame))
        end
        local elapsed=(os.clock()-captureStarted)*1000
        state.captureMs=state.captureMs and state.captureMs*.9+elapsed*.1 or elapsed
    end

    if state.diagnostics and os.time() ~= state.lastDiagnostic then
        state.lastDiagnostic = os.time()
        M.inspect()
    end
    -- Keep a compact timing record without requiring another console command
    -- after each reload. No actor inspection or per-frame disk writes.
    if now-(state.lastPerformanceReport or 0)>=2 then
        state.lastPerformanceReport=now
        local rows={string.format("capture_ms=%.2f render_ms=%.2f",state.captureMs or 0,state.ghosts.renderMs or 0)}
        for id,slot in pairs(state.ghosts.ghosts) do
            rows[#rows+1]=string.format("peer=%s frames=%d renders=%d shared_pose_parts=%d",id,slot.frames or 0,slot.renders or 0,slot.sharedParts or 0)
        end
        local f=io.open(state.box.dir.."/performance.txt","wb")
        if f then f:write(table.concat(rows,"\n"));f:close() end
    end
end

return M
