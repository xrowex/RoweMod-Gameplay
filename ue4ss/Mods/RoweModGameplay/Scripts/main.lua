--[[
    RoweMod Gameplay — live feel options for Rollout Inline.
    Applies NewMainCharacter fields after spawn. Does not replace the clothing overlay.
]]

local UEHelpers = require("UEHelpers")

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
        log("config speedMultiplier=" .. tostring(config.speedMultiplier))
        return true
    end
    log("could not read config.lua (" .. tostring(loaded) .. ") — using defaults")
    config = { speedMultiplier = 1.0 }
    return false
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

local function dump_skater()
    local skaters = find_skaters()
    if #skaters == 0 then
        log("dump: no pawn")
        return
    end
    local pawn = skaters[1]
    log("pawn " .. tostring(pawn:GetFullName()))
    local names = {
        "Speed", "CasualSpeedIncrease", "SprintSpeedIncrease", "PreviousSpeed",
        "MaxLinearForce", "MaxAngularForce", "Gravity", "SlomoSpeed",
        "MaxSpinSpeed", "MaxFlipSpeed", "JumpVelocity", "MinJumpHeight",
        "GrindMagnetStrength", "BalanceIntensity",
    }
    for _, name in ipairs(names) do
        local value = read_num(pawn, name)
        if value ~= nil then
            log("  " .. name .. " = " .. tostring(value))
        end
    end
end

load_config()

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
end)

RegisterConsoleCommandHandler("rowemod", function(FullCommand, Parameters, Ar)
    local cmd = Parameters[1] and string.lower(Parameters[1]) or "apply"
    if cmd == "reload" or cmd == "load" then
        load_config()
        apply_all(false)
        return true
    end
    if cmd == "dump" then
        dump_skater()
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
    log("usage: rowemod apply | rowemod speed 1.5 | rowemod dump | rowemod reload")
    apply_all(false)
    return true
end)

LoopAsync(4000, function()
    apply_all(true)
    return false
end)

log("loaded. Numpad +/- speed, F8 reload config, console: rowemod speed 1.5")
