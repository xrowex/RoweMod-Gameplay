--[[
    RoweMod Gameplay — live feel options for Rollout Inline.
    Applies NewMainCharacter fields after spawn. Does not replace the clothing overlay.
    Recon: rowemod recon / watch. Multiplayer: rowemod mp on (needs tools/rowemod_mp.py).
]]

local UEHelpers = require("UEHelpers")
local game_thread = require("game_thread")
local menu_values = require("menu_values")
local gravity_control = require("gravity")
local gravity_error

local mp_session = nil
pcall(function()
    mp_session = require("mp.session")
end)
if not mp_session then
    pcall(function()
        package.path = package.path .. ";./mp/?.lua;./?.lua"
        mp_session = require("mp.session")
    end)
end

local CONFIG_PATHS = {
    "Mods/RoweModGameplay/Scripts/config.lua",
    "ue4ss/Mods/RoweModGameplay/Scripts/config.lua",
}

local SPEED_FIELDS = { "CasualSpeedIncrease", "SprintSpeedIncrease" }

local NUMBER_FIELDS = {
    casualSpeedIncrease = "CasualSpeedIncrease",
    sprintSpeedIncrease = "SprintSpeedIncrease",
    maxLinearForce = "MaxLinearForce",
    maxAngularForce = "MaxAngularForce",
    gravity = "Gravity",
    slomoSpeed = "SlomoSpeed",
    jumpVelocity = "JumpVelocity",
    minJumpHeight = "MinJumpHeight",
    maxJumpHeight = "MaxJumpHeight",
    jumpPrepSteering = "JumpPrepSteering",
    grindMagnetStrength = "GrindMagnetStrength",
    grindMagnetSize = "GrindMagnetSize",
    balanceIntensity = "BalanceIntensity",
    balanceDriftIncrease = "BalanceDriftIncrease",
    balanceDriftStrength = "BalanceDriftStrength",
    baseBalanceDrift = "BaseBalanceDrift",
    maxSpinSpeed = "MaxSpinSpeed",
    maxFlipSpeed = "MaxFlipSpeed",
    spinMultiplier = "SpinMultiplier",
    flipMultiplier = "FlipMultiplier",
    grabSpinSpeedDivider = "GrabSpinSpeedDivider",
    steerMultiplier = "SteerMultiplier",
    steeringStrengthSetting = "SteeringStrengthSetting",
    cameraDistance = "CameraDistance",
    cameraHeight = "CameraHeight",
    cameraLookUp = "CameraLookUp",
    cameraSideOffset = "CameraSideOffset",
    airRotInterpSpeed = "AirRotInterpSpeed",
    comboMultiplier = "ComboMultiplier",
    forceFeedbackStrength = "ForceFeedbackStrength",
}

local BOOL_FIELDS = {
    requiresBalance = "RequiresBalance",
    showBalanceMeter = "ShowBalanceMeter",
    enableGrindSparks = "EnableGrindSparks",
    triggerSteering = "TriggerSteering",
    streamlinedControls = "StreamlinedControls",
    slowmotion = "Slowmotion",
}

local SAVE_CLASS_NAMES = { "SettingsSaveGame_C", "SettingsSaveGame" }

local config = { speedMultiplier = 1.0 }
local originals = {}
local save_originals = {}
local rowe_menu

local function log(msg)
    print("[RoweModGameplay] " .. tostring(msg))
end

local function notify(msg, duration)
    log(msg)
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local world = UEHelpers.GetWorld()
        if kismet and kismet:IsValid() and world and world:IsValid() then
            kismet:PrintString(world, "[RoweMod] " .. msg, true, true, { R = 0.2, G = 1.0, B = 0.7, A = 1.0 }, duration or 3.5)
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
        local saved = require("menu_store").load()
        for key, value in pairs(saved) do config[key] = value end
        for key,item in pairs(menu_values.items) do
            if item[3] ~= "bool" and config[key] ~= nil then
                if not menu_values.in_range(item,config[key]) then
                    log("resetting out-of-range " .. key .. " to " .. tostring(item.default))
                    config[key] = item.default
                else
                    config[key] = menu_values.snap(item,config[key])
                end
            end
        end
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
    local envName = os.getenv("ROUEMOD_MP_NAME")
    mpCfg.playerName = envName or mpCfg.playerName or "skater"
    local envMailbox = os.getenv("ROUEMOD_MP_MAILBOX")
    if envMailbox and envMailbox ~= "" and not mpCfg.online then
        mpCfg.mailboxDir = envMailbox
    end
    local envRole = os.getenv("ROUEMOD_MP_ROLE")
    if envRole and envRole ~= "" and not mpCfg.online then
        mpCfg.role = string.lower(envRole)
    end
    local role = mpCfg.online and "auto" or mpCfg.role or "auto"
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
            role = mpCfg.online and "join" or "host"
        end
    end
    mpCfg.role = role
    mpCfg.isHost = (role == "host")
    log(string.format("mp start role=%s name=%s mailbox=%s",
        tostring(role), tostring(mpCfg.playerName), tostring(mpCfg.mailboxDir or "(default)")))
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

local function read_bool(obj, name)
    local ok, value = pcall(function()
        return obj[name]
    end)
    if ok and type(value) == "boolean" then
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

local function write_bool(obj, name, value)
    if type(value) ~= "boolean" then
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
    for _, name in pairs(NUMBER_FIELDS) do
        if snap[name] == nil then
            snap[name] = read_num(pawn, name)
        end
    end
    for _, name in pairs(BOOL_FIELDS) do snap[name] = read_bool(pawn, name) end
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

local function find_of(classNames)
    local found = {}
    for _, className in ipairs(classNames) do
        local ok, list = pcall(FindAllOf, className)
        if ok and list then
            for _, obj in ipairs(list) do
                if obj and obj:IsValid() then
                    found[#found + 1] = obj
                end
            end
        end
    end
    return found
end

local function find_skaters()
    local found = find_of({ "NewMainCharacter_C", "NewMainCharacter" })
    if #found == 0 then
        local pawn = UEHelpers.GetPlayer()
        if pawn and pawn:IsValid() then
            found[1] = pawn
        end
    end
    return found
end

local function apply_overrides(obj)
    local n = 0
    for key, name in pairs(NUMBER_FIELDS) do
        if key ~= "casualSpeedIncrease" and key ~= "sprintSpeedIncrease" then
            local override = config[key]
            if type(override) == "number" and write_num(obj, name, override) then
                n = n + 1
            end
        end
    end
    for key, name in pairs(BOOL_FIELDS) do
        local override = config[key]
        if type(override) == "boolean" and write_bool(obj, name, override) then
            n = n + 1
        end
    end
    return n
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
    n = n + apply_overrides(pawn)
    return n
end

local function apply_saves()
    local n = 0
    for _, save in ipairs(find_of(SAVE_CLASS_NAMES)) do
        local id = pawn_id(save)
        if not save_originals[id] then
            local snap = {}
            for _, name in pairs(NUMBER_FIELDS) do snap[name] = read_num(save, name) end
            for _, name in pairs(BOOL_FIELDS) do snap[name] = read_bool(save, name) end
            save_originals[id] = snap
        end
        n = n + apply_overrides(save)
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
    total = total + apply_saves()
    local gravity_ok,detail=gravity_control.apply(config.gravityMultiplier,skaters)
    if not gravity_ok and detail~=gravity_error then log(detail) end
    gravity_error=not gravity_ok and detail or nil
    if not silent then
        notify(string.format("speed x%.2f  (%d fields)", config.speedMultiplier or 1.0, total))
    end
    return total
end

local function dump_known(obj, label)
    log(label .. " " .. tostring(obj:GetFullName()))
    local names = {}
    for _, name in pairs(NUMBER_FIELDS) do
        names[#names + 1] = name
    end
    for _, name in pairs(BOOL_FIELDS) do
        names[#names + 1] = name
    end
    table.sort(names)
    local seen = {}
    for _, name in ipairs(names) do
        if not seen[name] then
            seen[name] = true
            local num = read_num(obj, name)
            if num ~= nil then
                log("  " .. name .. " = " .. tostring(num))
            else
                local bool = read_bool(obj, name)
                if bool ~= nil then
                    log("  " .. name .. " = " .. tostring(bool))
                end
            end
        end
    end
end

local function dump_all_properties(obj)
    local class = nil
    local okClass = pcall(function()
        class = obj:GetClass()
    end)
    if not okClass or not class or not class:IsValid() then
        log("dump all: no class")
        return
    end
    log("all numeric/bool on " .. tostring(obj:GetFullName()))
    while class and class:IsValid() do
        local className = class:GetFullName()
        pcall(function()
            class:ForEachProperty(function(property)
                local name = property:GetFName():ToString()
                local num = read_num(obj, name)
                if num ~= nil then
                    log("  " .. name .. " = " .. tostring(num))
                    return
                end
                local bool = read_bool(obj, name)
                if bool ~= nil then
                    log("  " .. name .. " = " .. tostring(bool))
                end
            end)
        end)
        local nextClass = nil
        local okSuper = pcall(function()
            nextClass = class:GetSuperStruct()
        end)
        if not okSuper or nextClass == class then
            break
        end
        class = nextClass
        if className:find("Pawn") then
            break
        end
    end
end

local function dump_skater(deep)
    local skaters = find_skaters()
    if #skaters == 0 then
        log("dump: no pawn")
        return
    end
    dump_known(skaters[1], "pawn")
    local saves = find_of(SAVE_CLASS_NAMES)
    if #saves > 0 then
        dump_known(saves[1], "save")
    end
    if deep then
        dump_all_properties(skaters[1])
    end
end

local DUMP_SCALAR_NAMES = {
    "Speed", "CasualSpeedIncrease", "SprintSpeedIncrease", "PreviousSpeed",
    "MaxLinearForce", "MaxAngularForce", "Gravity", "SlomoSpeed",
    "MaxSpinSpeed", "MaxFlipSpeed", "JumpVelocity", "MinJumpHeight", "MaxJumpHeight",
    "GrindMagnetStrength", "GrindMagnetSize", "BalanceIntensity",
    "IsGrinding", "IsRagdoll", "IsGrabbing",
}

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

local apply_after_restart = game_thread.wrap(function() apply_all(false) end, 800)
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    apply_after_restart()
end)

RegisterKeyBind(Key.ADD, game_thread.wrap(function()
    config.speedMultiplier = math.min(4.0, (config.speedMultiplier or 1.0) + 0.1)
    apply_all(false)
end))

RegisterKeyBind(Key.SUBTRACT, game_thread.wrap(function()
    config.speedMultiplier = math.max(0.4, (config.speedMultiplier or 1.0) - 0.1)
    apply_all(false)
end))

RegisterKeyBind(Key.F8, game_thread.wrap(function()
    load_config()
    apply_all(false)
    mp_sync_from_config()
end))

RegisterKeyBind(Key.F7, game_thread.wrap(function()
    recon_all(true)
end))

RegisterKeyBind(Key.F6, game_thread.wrap(function()
    watch_enabled = not watch_enabled
    if watch_enabled then
        watch_snapshot = {}
        notify("watch ON — grind/trick prop changes → log")
    else
        notify("watch OFF")
    end
end))

RegisterKeyBind(Key.F9, game_thread.wrap(function()
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
end))

RegisterConsoleCommandHandler("rowemod", function(FullCommand, Parameters, Ar)
    local cmd = Parameters[1] and string.lower(Parameters[1]) or "apply"
    if cmd == "menu" then
        if rowe_menu then rowe_menu.toggle() end
        return true
    end
    if cmd == "reload" or cmd == "load" then
        load_config()
        apply_all(false)
        mp_sync_from_config()
        return true
    end
    if cmd == "dump" then
        local deep = Parameters[2] and string.lower(Parameters[2]) == "all"
        dump_skater(deep)
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
        if mode == "online" then
            local online = require("mp.online")
            local ok, detail = online.open(Parameters[3])
            if ok then
                mp_stop()
                online.configure(config)
                mp_start()
                notify("Steam companion opened; host or join a session there")
            else notify(detail) end
        elseif mode == "on" or mode == "start" then
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
        elseif mode == "inspect" then
            if mp_session then mp_session.inspect(Parameters[3] == "on") end
        elseif mode == "avatar" then
            if mp_session then mp_session.avatar_census() end
        elseif mode == "testmove" then
            if mp_session then mp_session.test_move(Parameters[3], Parameters[4]) end
        elseif mode == "reload" then
            mp_stop()
            for _, name in ipairs({ "mp.session", "mp.ghost", "mp.capture", "mp.mailbox", "mp.avatar", "mp.protocol" }) do
                package.loaded[name] = nil
            end
            mp_session = require("mp.session")
            notify("MP scripts reloaded; use rowemod mp on to reconnect")
        elseif mode == "status" then
            local s = mp_session and mp_session.status() or "mp module missing"
            -- The UE console routes print() to UE4SS.log. Keep the short
            -- status visible after the console is closed and save the fuller
            -- diagnostic report beside the Steam mailbox.
            if mp_session then mp_session.inspect(false) end
            notify(s, 10)
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
            local ok, detail = mp_session.travel(target)
            notify(ok and ("travel " .. tostring(target)) or ("travel fail: " .. tostring(detail)))
        else
            log("usage: rowemod mp online [lobby]|on|off|host|join|status|inspect|map [id]|travel [id]")
        end
        return true
    end
    if cmd == "speed" or cmd == "x" then
        local n = tonumber(Parameters[2])
        if n then
            config.speedMultiplier = menu_values.snap(menu_values.items.speedMultiplier, n) or 1.0
        end
        apply_all(false)
        return true
    end
    if cmd == "apply" or cmd == "on" then
        apply_all(false)
        return true
    end
    log("usage: rowemod apply | speed | dump [all] | recon | watch | mp on|off|host|join|status|map|travel | reload")
    apply_all(false)
    return true
end)

game_thread.loop(4000, function()
    apply_all(true)
    return false
end)

game_thread.loop(100, function()
    watch_tick()
    return false
end)

game_thread.loop(50, function()
    if mp_session and mp_session.is_active() then
        local ok, err = pcall(mp_session.tick)
        if not ok then
            log("mp tick error: " .. tostring(err))
        end
    end
    return false
end)

load_config()
local menu_ok, menu_error = pcall(function()
    local menu = require("rowe_menu")
    local fields = {}
    for _, group in ipairs(require("menu_schema")) do
        for _, item in ipairs(group.items) do fields[item[1]] = item end
    end
    local api = {}
    function api.get(key)
        if key=="gravityMultiplier" then
            if not gravity_control.available() then return nil end
            return config[key] or 1.0
        end
        if config[key] ~= nil then return config[key] end
        local pawn = require("mp.capture").local_pawn()
        if not pawn then return nil end
        local field = NUMBER_FIELDS[key] or BOOL_FIELDS[key]
        if BOOL_FIELDS[key] then return read_bool(pawn, field) end
        return read_num(pawn, field)
    end
    function api.set(key, value)
        local item = fields[key]
        if not item then return false end
        if item[3] == "bool" then
            if type(value) ~= "boolean" then return false end
        else
            value = menu_values.snap(item,value)
            if value == nil then return false end
        end
        if key=="gravityMultiplier" then
            local ok,detail=gravity_control.apply(value,find_skaters())
            if not ok then log(detail);return false end
        end
        config[key] = value
        apply_all(true)
        return true
    end
    function api.reset(key)
        if not fields[key] then return end
        if key=="gravityMultiplier" then config[key]=nil;apply_all(true);return end
        if key == "speedMultiplier" then config[key] = 1.0; apply_all(true); return end
        config[key] = nil
        local field = NUMBER_FIELDS[key] or BOOL_FIELDS[key]
        for _, actor in ipairs(find_skaters()) do
            local snap = originals[pawn_id(actor)]
            if snap and snap[field] ~= nil then
                if BOOL_FIELDS[key] then write_bool(actor,field,snap[field]) else
                    local value=menu_values.in_range(fields[key],snap[field]) and snap[field] or fields[key].default
                    write_num(actor,field,value)
                end
            end
        end
        for _, save in ipairs(find_of(SAVE_CLASS_NAMES)) do
            local snap = save_originals[pawn_id(save)]
            if snap and snap[field] ~= nil then
                if BOOL_FIELDS[key] then write_bool(save,field,snap[field]) else
                    local value=menu_values.in_range(fields[key],snap[field]) and snap[field] or fields[key].default
                    write_num(save,field,value)
                end
            end
        end
        apply_all(true)
    end
    function api.save() return require("menu_store").save(config) end
    local online_page = require("menu_online")
    online_page.init({
        connect = function()
            if not config.mp.online or not mp_session.is_active() then
                mp_stop(); require("mp.online").configure(config); mp_start()
            end
        end,
        disconnect = function() config.mp.enabled=false;mp_stop() end,
        status = function() return mp_session.status() end,
        map_status = function() return mp_session.map_status() end,
        retry_map = function() return mp_session.retry_map() end,
    })
    api.multiplayer = online_page.build
    api.tick = online_page.tick
    api.unmount = online_page.unmount
    if online_page.update then game_thread.loop(250,online_page.update) end
    menu.init(api)
    rowe_menu = menu
end)
if not menu_ok then log("menu initialization failed: " .. tostring(menu_error)) end
game_thread.wrap(function()
    pcall(function() require("mp.online").boot(config) end)
    mp_sync_from_config()
    pcall(function() require("auto_update").check() end)
end)()

log("loaded. F5 menu, F9 mp toggle, F7 recon, F6 watch, F8 reload; console: rowemod menu")
