--[[
    Multiplayer session: capture local skater → mailbox → bridge → peers,
    apply remote packets onto ghost skaters (tricks/grinds + transform).

    Peers must share the same mapId. Until they do, gameplay sync is gated.
]]

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

local function refresh_local_map()
    local info = mapinfo.current()
    local id = info.id or "unknown"
    if id ~= state.localMapId then
        local prev = state.localMapId
        state.localMapId = id
        if state.active and prev and prev ~= "unknown" then
            send_line(protocol.encode_map(next_seq(), id))
            send_line(protocol.encode_hello(next_seq(), state.playerName, id))
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

local function host_map_authority()
    local cfg = state.cfg or {}
    if cfg.hostMapAuthority == nil then
        return true
    end
    return not not cfg.hostMapAuthority
end

local function maps_in_sync()
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
    for peerId, mapId in pairs(state.peerMaps) do
        if not mapinfo.same(mapId, target) then
            return false
        end
    end
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
        notify("host map=" .. want .. " — rowemod mp travel  (or enable autoTravelToHostMap)")
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
        log(string.format("hello from %s map=%s", tostring(msg.name), peerMap))
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
        handle_map_req(msg)
        return
    end

    if msg.type == "map_ack" then
        state.peerMaps[peerId] = mapinfo.normalize(msg.mapId or "unknown")
        recompute_match()
        log(string.format("map_ack peer=%s map=%s ok=%s", peerId, tostring(msg.mapId), tostring(msg.ok)))
        return
    end

    if msg.type == "bye" then
        state.ghosts:remove(peerId)
        state.peerNames[peerId] = nil
        state.peerMaps[peerId] = nil
        recompute_match()
        return
    end

    -- Gameplay packets only when maps agree (and peer is on our map).
    local peerMap = state.peerMaps[peerId]
    if require_same_map() then
        if not state.mapsMatched then
            return
        end
        if peerMap and not mapinfo.same(peerMap, state.localMapId) then
            return
        end
    end

    if msg.type == "transform" then
        state.ghosts:apply_transform(peerId, msg)
    elseif msg.type == "grind_enter" then
        state.ghosts:apply_grind_enter(peerId, msg)
    elseif msg.type == "grind_update" then
        state.ghosts:apply_grind_update(peerId, msg)
    elseif msg.type == "grind_exit" then
        state.ghosts:apply_grind_exit(peerId, msg)
    elseif msg.type == "grab" then
        state.ghosts:apply_grab(peerId, msg)
    elseif msg.type == "bail" then
        state.ghosts:apply_bail(peerId)
    elseif msg.type == "land" then
        -- reserved
    end
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

function M.status()
    if not state.active then
        return "mp off"
    end
    local bridge = state.box and state.box:read_bridge_status() or "?"
    local peers = 0
    for _ in pairs(state.peerNames) do
        peers = peers + 1
    end
    return string.format(
        "mp on map=%s session=%s ok=%s peers=%d bridge=%s",
        tostring(state.localMapId),
        tostring(state.sessionMapId or "?"),
        tostring(state.mapsMatched),
        peers,
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
    state.seq = 0
    state.peerNames = {}
    state.peerMaps = {}
    state.mapsMatched = false
    state.pendingTravel = nil
    state.active = true
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
    send_hello()
    if state.isHost then
        send_line(protocol.encode_map_req(next_seq(), state.localMapId))
    end
    recompute_match()
    log("session started map=" .. state.localMapId .. " mailbox=" .. state.box.dir)
    notify("MP on map=" .. state.localMapId)
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
    state.box = nil
    state.ghosts = nil
    state.prevSnap = nil
    state.peerNames = {}
    state.peerMaps = {}
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
    state.sessionMapId = mapId
    state.isHost = true
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

    refresh_local_map()
    recompute_match()

    local lines = state.box:poll_inbox(48)
    for _, line in ipairs(lines) do
        local ok, err = pcall(handle_packet, line, "peer")
        if not ok then
            log("handle err: " .. tostring(err))
        end
    end

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
    local snap = capture.snapshot(pawn, state.propMap)
    if not snap then
        return
    end

    -- Scope rails to map so G+ ids are unique across levels.
    if snap.railId and snap.railId ~= "" then
        snap.railId = scope_rail(snap.railId)
    end

    local events = capture.diff_events(state.prevSnap, snap)
    for _, ev in ipairs(events) do
        local seq = next_seq()
        if ev.kind == "grind_enter" then
            ev.railId = scope_rail(ev.railId)
            send_line(protocol.encode_grind_enter(seq, ev))
            log("local grind+ " .. tostring(ev.railId))
        elseif ev.kind == "grind_update" then
            send_line(protocol.encode_grind_update(seq, ev))
        elseif ev.kind == "grind_exit" then
            send_line(protocol.encode_grind_exit(seq, ev))
            log("local grind- " .. tostring(ev.reason))
        elseif ev.kind == "grab" then
            send_line(protocol.encode_grab(seq, ev.grabId))
            log("local grab " .. tostring(ev.grabId))
        elseif ev.kind == "bail" then
            send_line(protocol.encode_bail(seq))
            log("local bail")
        end
    end

    local hz = (state.cfg and state.cfg.transformHz) or 20
    local now = os.clock()
    local minDt = 1.0 / math.max(5, hz)
    if (now - (state.lastTransformSent or 0)) >= minDt then
        state.lastTransformSent = now
        send_line(protocol.encode_transform(next_seq(), snap.transform))
    end

    state.prevSnap = snap
end

return M
