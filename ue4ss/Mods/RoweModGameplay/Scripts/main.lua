--[[
    RoweMod Gameplay — live feel options for Rollout Inline.
    Applies NewMainCharacter fields after spawn. Does not replace the clothing overlay.
    Recon: rowemod recon / watch. Multiplayer: rowemod mp on (needs tools/rowemod_mp.py).
]]

local UEHelpers = require("UEHelpers")

local mp_session = nil
pcall(function()
    mp_session = require("mp.session")
end)
if not mp_session then
    pcall(function()
        -- Older package.path layouts
        package.path = package.path .. ";./mp/?.lua;./?.lua"
        mp_session = require("mp.session")
    end)
end

local CONFIG_PATHS = {
    "Mods/RoweModGameplay/Scripts/config.lua",
    "ue4ss/Mods/RoweModGameplay/Scripts/config.lua",
}

local SPEED_FIELDS = { "CasualSpeedIncrease", "SprintSpeedIncrease" }
local OPTIONAL_FIELDS = {
    casualSpeedIncrease = "CasualSpeedIncrease",
    sprintSpeedIncrease = "SprintSpeedIncrease",
    maxLinearForce = "MaxLinearForce",
    maxAngularForce = "MaxAngularForce",
    gravity = "Gravity",
    slomoSpeed = "SlomoSpeed",
}

local config = { speedMultiplier = 1.0 }
local originals = {}

local function log(msg)
    print("[RoweModGameplay] " .. tostring(msg))
end

local function notify(msg)
    log(msg)
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local world = UEHelpers.GetWorld()
        if kismet and kismet:IsValid() and world and world:IsValid() then
            kismet:PrintString(world, "[RoweMod] " .. msg, true, true, { R = 0.2, G = 1.0, B = 0.7, A = 1.0 }, 3.5)
        end
    end)
end

local function load_config()
    package.loaded["config"] = nil
    local loaded = nil
    local ok = false
    ok, loaded = pcall(require, "config")
    if not ok or type(loaded) ~= "table" then
        for _, path in ipairs(CONFIG_PATHS) do
            ok, loaded = pcall(dofile, path)
            if ok and type(loaded) == "table" then
                break
            end
        end
    end
    if ok and type(loaded) == "table" then
        config = loaded
        if type(config.speedMultiplier) ~= "number" then
            config.speedMultiplier = 1.0
        end
        if type(config.mp) ~= "table" then
            config.mp = { enabled = false }
        end
        log("config speedMultiplier=" .. tostring(config.speedMultiplier))
        return true
    end
    log("could not read config.lua (" .. tostring(loaded) .. ") — using defaults")
    config = { speedMultiplier = 1.0, mp = { enabled = false } }
    return false
end

local function mp_notify(msg)
    notify(msg)
end

local function mp_start()
    if not mp_session then
        notify("MP module missing")
        return false
    end
    local mpCfg = config.mp or {}
    mpCfg.playerName = mpCfg.playerName or "skater"
    -- Resolve host/join from config or bridge status.
    local role = mpCfg.role or "auto"
    if role == "auto" then
        local status = nil
        pcall(function()
            local mailbox = require("mp.mailbox")
            local box = mailbox.open(mpCfg.mailboxDir)
            status = box:read_bridge_status()
        end)
        if status and string.find(string.lower(status), "host", 1, true) then
            role = "host"
        elseif status and string.find(string.lower(status), "join", 1, true) then
            role = "join"
        else
            role = "host"
        end
    end
    mpCfg.role = role
    mpCfg.isHost = (role == "host")
    return mp_session.start(mpCfg, mp_notify)
end

local function mp_stop()
    if mp_session then
        mp_session.stop(mp_notify)
    end
end

local function mp_sync_from_config()
    if not mp_session then
        return
    end
    local want = config.mp and config.mp.enabled
    if want and not mp_session.is_active() then
        mp_start()
    elseif (not want) and mp_session.is_active() then
        mp_stop()
    end
end

local function read_num(obj, name)
    local ok, value = pcall(function()
        return obj[name]
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function write_num(obj, name, value)
    if type(value) ~= "number" then
        return false
    end
    local ok, err = pcall(function()
        obj[name] = value
    end)
    if not ok then
        log("set " .. name .. " failed: " .. tostring(err))
        return false
    end
    return true
end

local function pawn_id(pawn)
    local ok, addr = pcall(function()
        return string.format("%s:%X", pawn:GetFullName(), pawn:GetAddress())
    end)
    if ok then
        return addr
    end
    return tostring(pawn)
end

local function capture_originals(pawn)
    local id = pawn_id(pawn)
    if originals[id] then
        return originals[id]
    end
    local snap = {}
    for _, name in ipairs(SPEED_FIELDS) do
        snap[name] = read_num(pawn, name)
    end
    for _, name in pairs(OPTIONAL_FIELDS) do
        if snap[name] == nil then
            snap[name] = read_num(pawn, name)
        end
    end
    local usable = false
    for _, name in ipairs(SPEED_FIELDS) do
        if snap[name] and snap[name] ~= 0 then
            usable = true
            break
        end
    end
    if usable then
        originals[id] = snap
    end
    return snap
end

local function find_skaters()
    local found = {}
    for _, className in ipairs({ "NewMainCharacter_C", "NewMainCharacter" }) do
        local ok, list = pcall(FindAllOf, className)
        if ok and list then
            for _, obj in ipairs(list) do
                if obj and obj:IsValid() then
                    found[#found + 1] = obj
                end
            end
        end
    end
    if #found == 0 then
        local pawn = UEHelpers.GetPlayer()
        if pawn and pawn:IsValid() then
            found[1] = pawn
        end
    end
    return found
end

local function apply_one(pawn)
    local snap = capture_originals(pawn)
    local n = 0
    local mult = config.speedMultiplier or 1.0
    for _, name in ipairs(SPEED_FIELDS) do
        local key = (name == "CasualSpeedIncrease") and "casualSpeedIncrease" or "sprintSpeedIncrease"
        local override = config[key]
        local value = nil
        if type(override) == "number" then
            value = override
        elseif snap[name] ~= nil then
            value = snap[name] * mult
        end
        if value ~= nil and write_num(pawn, name, value) then
            n = n + 1
        end
    end
    for key, name in pairs(OPTIONAL_FIELDS) do
        if key ~= "casualSpeedIncrease" and key ~= "sprintSpeedIncrease" then
            local override = config[key]
            if type(override) == "number" then
                if write_num(pawn, name, override) then
                    n = n + 1
                end
            end
        end
    end
    return n
end

local function apply_all(silent)
    local skaters = find_skaters()
    if #skaters == 0 then
        if not silent then
            log("no skater pawn yet")
        end
        return 0
    end
    local total = 0
    for _, pawn in ipairs(skaters) do
        total = total + apply_one(pawn)
    end
    if not silent then
        notify(string.format("speed x%.2f  (%d fields)", config.speedMultiplier or 1.0, total))
    end
    return total
end

-- Known feel / trick-adjacent scalars (many may be nil until confirmed in-game).
local DUMP_SCALAR_NAMES = {
    "Speed", "CasualSpeedIncrease", "SprintSpeedIncrease", "PreviousSpeed",
    "MaxLinearForce", "MaxAngularForce", "Gravity", "SlomoSpeed",
    "MaxSpinSpeed", "MaxFlipSpeed", "JumpVelocity", "MinJumpHeight",
    "GrindMagnetStrength", "BalanceIntensity",
}

-- Name substrings that usually matter for trick/grind recon.
local RECON_HINTS = {
    "grind", "rail", "ledge", "balance", "trick", "grab", "spin", "flip",
    "plant", "manual", "cess", "stance", "combo", "montage", "anim",
    "skate", "wheel", "magnet", "bail", "ragdoll", "air", "jump",
}

local watch_enabled = false
local watch_snapshot = {}

local function value_to_string(value)
    if value == nil then
        return "nil"
    end
    local t = type(value)
    if t == "number" or t == "boolean" or t == "string" then
        return tostring(value)
    end
    local ok, asObj = pcall(function()
        if value.IsValid and value:IsValid() and value.GetFullName then
            return value:GetFullName()
        end
        if value.ToString then
            return value:ToString()
        end
        return nil
    end)
    if ok and asObj then
        return asObj
    end
    return tostring(value)
end

local function dump_skater()
    local skaters = find_skaters()
    if #skaters == 0 then
        log("dump: no pawn")
        return
    end
    local pawn = skaters[1]
    log("pawn " .. tostring(pawn:GetFullName()))
    for _, name in ipairs(DUMP_SCALAR_NAMES) do
        local value = read_num(pawn, name)
        if value ~= nil then
            log("  " .. name .. " = " .. tostring(value))
        end
    end
end

local function name_is_interesting(name)
    local lower = string.lower(name)
    for _, hint in ipairs(RECON_HINTS) do
        if string.find(lower, hint, 1, true) then
            return true
        end
    end
    return false
end

local function recon_pawn(pawn, interesting_only)
    log("recon pawn " .. tostring(pawn:GetFullName()))
    local propCount = 0
    local interesting = 0
    local okProps = pcall(function()
        local classObj = pawn:GetClass()
        while classObj and classObj:IsValid() do
            log("  --- " .. classObj:GetFullName() .. " ---")
            classObj:ForEachProperty(function(prop)
                local name = prop:GetFName():ToString()
                propCount = propCount + 1
                local show = (not interesting_only) or name_is_interesting(name)
                if show then
                    interesting = interesting + 1
                    local ok, value = pcall(function()
                        return pawn[name]
                    end)
                    local typeName = "?"
                    pcall(function()
                        typeName = prop:GetClass():GetFName():ToString()
                    end)
                    if ok then
                        log(string.format("  prop [%s] %s = %s", typeName, name, value_to_string(value)))
                    else
                        log(string.format("  prop [%s] %s = <unreadable>", typeName, name))
                    end
                end
            end)
            classObj = classObj:GetSuperStruct()
        end
    end)
    if not okProps then
        log("  class property walk failed — fall back to known scalars")
        for _, name in ipairs(DUMP_SCALAR_NAMES) do
            local value = read_num(pawn, name)
            if value ~= nil then
                log("  " .. name .. " = " .. tostring(value))
            end
        end
    else
        log(string.format("  properties scanned=%d shown=%d (interesting_only=%s)",
            propCount, interesting, tostring(interesting_only and true or false)))
    end

    local fnCount = 0
    local fnShown = 0
    local okFns = pcall(function()
        local classObj = pawn:GetClass()
        while classObj and classObj:IsValid() do
            if classObj.ForEachFunction then
                classObj:ForEachFunction(function(fn)
                    local name = fn:GetFName():ToString()
                    fnCount = fnCount + 1
                    if (not interesting_only) or name_is_interesting(name) then
                        fnShown = fnShown + 1
                        log("  fn " .. name)
                    end
                end)
            end
            classObj = classObj:GetSuperStruct()
        end
    end)
    if okFns then
        log(string.format("  functions scanned=%d shown=%d", fnCount, fnShown))
    else
        log("  function walk unavailable — use CXX dump (Ctrl+H) for UFunctions")
    end
end

local function recon_world_objects()
    log("recon: scanning loaded UObjects for grind/trick-related names")
    local hits = 0
    local ok = pcall(function()
        ForEachUObject(function(obj)
            if not obj or not obj:IsValid() then
                return
            end
            local okName, full = pcall(function()
                return obj:GetFullName()
            end)
            if not okName or not full then
                return
            end
            if name_is_interesting(full) then
                hits = hits + 1
                if hits <= 200 then
                    log("  obj " .. full)
                end
            end
        end)
    end)
    if not ok then
        -- Fallback: probe a few likely short class names.
        log("  ForEachUObject unavailable — probing FindAllOf short names")
        local guesses = {
            "NewMainCharacter_C", "NewMainCharacter",
            "Grind", "Rail", "Balance", "Trick", "Grab",
        }
        for _, name in ipairs(guesses) do
            local foundOk, list = pcall(FindAllOf, name)
            if foundOk and list then
                for _, obj in ipairs(list) do
                    if obj and obj:IsValid() then
                        hits = hits + 1
                        log("  FindAllOf(" .. name .. ") -> " .. obj:GetFullName())
                    end
                end
            end
        end
    end
    log(string.format("recon: object name hits=%d%s", hits, hits > 200 and " (truncated after 200)" or ""))
end

local function recon_all(interesting_only)
    local skaters = find_skaters()
    if #skaters == 0 then
        log("recon: no pawn")
        notify("recon: no skater yet")
        return
    end
    for _, pawn in ipairs(skaters) do
        recon_pawn(pawn, interesting_only)
    end
    recon_world_objects()
    notify(interesting_only and "recon (hints) done — check UE4SS log"
        or "recon (full) done — check UE4SS log")
end

local function capture_watch_values(pawn)
    local snap = {}
    for _, name in ipairs(DUMP_SCALAR_NAMES) do
        snap[name] = read_num(pawn, name)
    end
    -- Best-effort: also sample any currently readable interesting props.
    pcall(function()
        local classObj = pawn:GetClass()
        while classObj and classObj:IsValid() do
            classObj:ForEachProperty(function(prop)
                local name = prop:GetFName():ToString()
                if name_is_interesting(name) then
                    local ok, value = pcall(function()
                        return pawn[name]
                    end)
                    if ok then
                        local s = value_to_string(value)
                        if #s < 180 then
                            snap[name] = s
                        end
                    end
                end
            end)
            classObj = classObj:GetSuperStruct()
        end
    end)
    return snap
end

local function watch_tick()
    if not watch_enabled then
        return true
    end
    local skaters = find_skaters()
    if #skaters == 0 then
        return false
    end
    local pawn = skaters[1]
    local id = pawn_id(pawn)
    local now = capture_watch_values(pawn)
    local prev = watch_snapshot[id]
    if prev then
        for key, value in pairs(now) do
            if prev[key] ~= value then
                log(string.format("watch %s: %s -> %s", key, tostring(prev[key]), tostring(value)))
            end
        end
        for key, value in pairs(prev) do
            if now[key] == nil and value ~= nil then
                log(string.format("watch %s: %s -> <gone>", key, tostring(value)))
            end
        end
    else
        log("watch: baseline captured for " .. tostring(pawn:GetFullName()))
    end
    watch_snapshot[id] = now
    return false
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ExecuteWithDelay(800, function()
        apply_all(false)
    end)
end)

RegisterKeyBind(Key.ADD, function()
    config.speedMultiplier = math.min(4.0, (config.speedMultiplier or 1.0) + 0.1)
    apply_all(false)
end)

RegisterKeyBind(Key.SUBTRACT, function()
    config.speedMultiplier = math.max(0.4, (config.speedMultiplier or 1.0) - 0.1)
    apply_all(false)
end)

RegisterKeyBind(Key.F8, function()
    load_config()
    apply_all(false)
    mp_sync_from_config()
end)

RegisterKeyBind(Key.F7, function()
    recon_all(true)
end)

RegisterKeyBind(Key.F6, function()
    watch_enabled = not watch_enabled
    if watch_enabled then
        watch_snapshot = {}
        notify("watch ON — grind/trick prop changes → log")
    else
        notify("watch OFF")
    end
end)

RegisterKeyBind(Key.F9, function()
    if not mp_session then
        notify("MP module missing")
        return
    end
    if mp_session.is_active() then
        if config.mp then
            config.mp.enabled = false
        end
        mp_stop()
    else
        if not config.mp then
            config.mp = {}
        end
        config.mp.enabled = true
        mp_start()
    end
end)

RegisterConsoleCommandHandler("rowemod", function(FullCommand, Parameters, Ar)
    local cmd = Parameters[1] and string.lower(Parameters[1]) or "apply"
    if cmd == "reload" or cmd == "load" then
        load_config()
        apply_all(false)
        mp_sync_from_config()
        return true
    end
    if cmd == "dump" then
        dump_skater()
        return true
    end
    if cmd == "recon" then
        local mode = Parameters[2] and string.lower(Parameters[2]) or "hints"
        recon_all(mode ~= "full" and mode ~= "all")
        return true
    end
    if cmd == "watch" then
        local mode = Parameters[2] and string.lower(Parameters[2]) or nil
        if mode == "off" or mode == "stop" then
            watch_enabled = false
            notify("watch OFF")
        elseif mode == "on" or mode == "start" or mode == nil then
            watch_enabled = true
            watch_snapshot = {}
            notify("watch ON — grind/trick prop changes → log")
        else
            log("usage: rowemod watch [on|off]")
        end
        return true
    end
    if cmd == "mp" then
        local mode = Parameters[2] and string.lower(Parameters[2]) or "status"
        if mode == "on" or mode == "start" then
            if not config.mp then
                config.mp = {}
            end
            config.mp.enabled = true
            if Parameters[3] then
                config.mp.playerName = Parameters[3]
            end
            mp_start()
        elseif mode == "off" or mode == "stop" then
            if config.mp then
                config.mp.enabled = false
            end
            mp_stop()
        elseif mode == "host" or mode == "join" then
            if not config.mp then
                config.mp = {}
            end
            config.mp.enabled = true
            config.mp.role = mode
            if Parameters[3] then
                config.mp.playerName = Parameters[3]
            end
            mp_start()
        elseif mode == "status" then
            local s = mp_session and mp_session.status() or "mp module missing"
            notify(s)
            log(s)
        elseif mode == "map" then
            if not mp_session then
                notify("MP module missing")
                return true
            end
            local mapinfo = require("mp.mapinfo")
            local info = mapinfo.current()
            local arg = Parameters[3]
            if arg and arg ~= "" then
                -- rowemod mp map <id>  → request peers to this map (host authority)
                local ok, detail = mp_session.request_map(arg)
                notify(ok and ("map req " .. tostring(detail)) or tostring(detail))
            else
                notify("map=" .. tostring(info.id) .. "  " .. (mp_session.status and mp_session.status() or ""))
                log("map raw=" .. tostring(info.raw))
            end
        elseif mode == "travel" then
            if not mp_session then
                notify("MP module missing")
                return true
            end
            local target = Parameters[3]
            if not target or target == "" then
                target = mp_session.local_map and mp_session.local_map() or nil
            end
            -- Prefer session map from host if traveling without arg
            if (not Parameters[3] or Parameters[3] == "") and mp_session.status then
                -- travel to session map announced by host
            end
            local ok, detail = mp_session.travel(target)
            notify(ok and ("travel " .. tostring(target)) or ("travel fail: " .. tostring(detail)))
        else
            log("usage: rowemod mp on|off|host|join|status|map [id]|travel [id]")
        end
        return true
    end
    if cmd == "speed" or cmd == "x" then
        local n = tonumber(Parameters[2])
        if n then
            config.speedMultiplier = math.max(0.2, math.min(5.0, n))
        end
        apply_all(false)
        return true
    end
    if cmd == "apply" or cmd == "on" then
        apply_all(false)
        return true
    end
    log("usage: rowemod apply | speed | dump | recon | watch | mp on|off|host|join|status|map|travel | reload")
    apply_all(false)
    return true
end)

LoopAsync(4000, function()
    apply_all(true)
    return false
end)

LoopAsync(100, function()
    watch_tick()
    return false
end)

LoopAsync(50, function()
    if mp_session and mp_session.is_active() then
        local ok, err = pcall(mp_session.tick)
        if not ok then
            log("mp tick error: " .. tostring(err))
        end
    end
    return false
end)

load_config()
mp_sync_from_config()

log("loaded. F9 mp toggle, F7 recon, F6 watch, F8 reload; console: rowemod mp on")
