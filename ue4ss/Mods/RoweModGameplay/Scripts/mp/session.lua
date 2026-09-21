--[[
    Multiplayer session: capture local skater → mailbox → bridge → peers,
    apply remote packets onto ghost skaters (tricks/grinds + transform).
]]

local protocol = require("mp.protocol")
local mailbox = require("mp.mailbox")
local capture = require("mp.capture")
local ghost = require("mp.ghost")

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

local function send_hello()
    send_line(protocol.encode_hello(next_seq(), state.playerName))
end

local function handle_packet(line, defaultPeer)
    -- Bridge may prefix: @peerId|RAW
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
        state.ghosts:ensure(peerId, msg.name)
        log("hello from " .. tostring(msg.name) .. " (" .. peerId .. ")")
        return
    end
    if msg.type == "bye" then
        state.ghosts:remove(peerId)
        state.peerNames[peerId] = nil
        return
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

function M.status()
    if not state.active then
        return "mp off"
    end
    local bridge = state.box and state.box:read_bridge_status() or "?"
    local peers = 0
    for _ in pairs(state.peerNames) do
        peers = peers + 1
    end
    return string.format("mp on peers=%d bridge=%s", peers, tostring(bridge))
end

function M.start(cfg, notify_fn)
    if state.active then
        M.stop()
    end
    cfg = cfg or {}
    state.cfg = cfg
    state.playerName = cfg.playerName or "skater"
    state.propMap = capture.merge_prop_map(cfg.props)
    state.box = mailbox.open(cfg.mailboxDir)
    state.ghosts = ghost.create_manager(state.propMap)
    state.prevSnap = nil
    state.seq = 0
    state.active = true
    state.box:write_status("game_up name=" .. state.playerName)
    send_hello()
    log("session started mailbox=" .. state.box.dir)
    if notify_fn then
        notify_fn("MP on — start tools/rowemod_mp.py")
    end
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
    log("session stopped")
    if notify_fn then
        notify_fn("MP off")
    end
end

function M.tick()
    if not state.active then
        return
    end

    -- Inbound
    local lines = state.box:poll_inbox(48)
    for _, line in ipairs(lines) do
        local ok, err = pcall(handle_packet, line, "peer")
        if not ok then
            log("handle err: " .. tostring(err))
        end
    end

    -- Outbound
    local pawn = capture.local_pawn()
    if not pawn then
        return
    end
    local snap = capture.snapshot(pawn, state.propMap)
    if not snap then
        return
    end

    local events = capture.diff_events(state.prevSnap, snap)
    for _, ev in ipairs(events) do
        local seq = next_seq()
        if ev.kind == "grind_enter" then
            send_line(protocol.encode_grind_enter(seq, ev))
            log("local grind+")
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
