--[[
    Capture local skater transform + grind/trick-ish state.
    Property names are configurable because the live dump is incomplete.
]]

local UEHelpers = require("UEHelpers")

local M = {}

local DEFAULT_PROPS = {
    grinding = { "bIsGrinding", "IsGrinding", "Grinding", "OnGrind", "bOnRail" },
    balance = { "Balance", "BalanceMeter", "CurrentBalance", "GrindBalance" },
    stance = { "GrindStance", "Stance", "GrindType", "CurrentGrind", "GrindName" },
    grab = { "CurrentGrab", "GrabType", "Grab", "ActiveGrab" },
    rail = { "CurrentRail", "GrindRail", "Rail", "GrindActor", "ActiveRail" },
    splineT = { "GrindDistance", "RailAlpha", "SplineDistance", "GrindAlpha", "RailDistance" },
    bail = { "bIsRagdoll", "IsRagdoll", "bBail", "Ragdolling" },
}

local function first_prop(obj, names)
    if not obj or not names then
        return nil, nil
    end
    for _, name in ipairs(names) do
        local ok, value = pcall(function()
            return obj[name]
        end)
        if ok and value ~= nil then
            local skip = false
            if type(value) == "userdata" then
                local okValid, valid = pcall(function()
                    return value.IsValid and value:IsValid()
                end)
                if okValid and valid == false then
                    skip = true
                end
            end
            if not skip then
                return name, value
            end
        end
    end
    return nil, nil
end

local function as_bool(value)
    if value == nil then
        return false
    end
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) == "string" then
        local lower = value:lower()
        return lower == "true" or lower == "1" or lower == "yes"
    end
    return not not value
end

local function as_num(value)
    if type(value) == "number" then
        return value
    end
    return tonumber(value) or 0
end

local function as_name(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    if type(value) == "number" then
        return tostring(value)
    end
    local ok, s = pcall(function()
        if value.ToString then
            return value:ToString()
        end
        if value.GetFullName then
            return value:GetFullName()
        end
        if value.GetFName then
            return value:GetFName():ToString()
        end
        return tostring(value)
    end)
    if ok and s then
        return tostring(s)
    end
    return ""
end

local function read_transform(pawn)
    local t = { x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0, vx = 0, vy = 0, vz = 0 }
    pcall(function()
        local loc = pawn:K2_GetActorLocation()
        if loc then
            t.x = loc.X or loc.x or 0
            t.y = loc.Y or loc.y or 0
            t.z = loc.Z or loc.z or 0
        end
    end)
    pcall(function()
        local rot = pawn:K2_GetActorRotation()
        if rot then
            t.pitch = rot.Pitch or rot.pitch or 0
            t.yaw = rot.Yaw or rot.yaw or 0
            t.roll = rot.Roll or rot.roll or 0
        end
    end)
    pcall(function()
        local root = pawn.RootComponent or pawn.CapsuleComponent or pawn.Mesh
        if root and root.GetPhysicsLinearVelocity then
            local v = root:GetPhysicsLinearVelocity()
            if v then
                t.vx = v.X or v.x or 0
                t.vy = v.Y or v.y or 0
                t.vz = v.Z or v.z or 0
            end
        end
    end)
    -- Fallback velocity from Speed scalar if present.
    if t.vx == 0 and t.vy == 0 and t.vz == 0 then
        local ok, speed = pcall(function()
            return pawn.Speed
        end)
        if ok and type(speed) == "number" then
            local yawRad = math.rad(t.yaw)
            t.vx = math.cos(yawRad) * speed
            t.vy = math.sin(yawRad) * speed
        end
    end
    return t
end

function M.merge_prop_map(cfgProps)
    local map = {}
    for key, defaults in pairs(DEFAULT_PROPS) do
        map[key] = {}
        local custom = cfgProps and cfgProps[key]
        if type(custom) == "string" then
            map[key][#map[key] + 1] = custom
        elseif type(custom) == "table" then
            for _, n in ipairs(custom) do
                map[key][#map[key] + 1] = n
            end
        end
        for _, n in ipairs(defaults) do
            map[key][#map[key] + 1] = n
        end
    end
    return map
end

function M.snapshot(pawn, propMap)
    if not pawn or not pawn:IsValid() then
        return nil
    end
    propMap = propMap or M.merge_prop_map(nil)
    local t = read_transform(pawn)
    local _, grinding = first_prop(pawn, propMap.grinding)
    local _, balance = first_prop(pawn, propMap.balance)
    local _, stance = first_prop(pawn, propMap.stance)
    local _, grab = first_prop(pawn, propMap.grab)
    local railName, rail = first_prop(pawn, propMap.rail)
    local _, splineT = first_prop(pawn, propMap.splineT)
    local _, bail = first_prop(pawn, propMap.bail)

    local railId = ""
    if rail ~= nil then
        railId = as_name(rail)
    end

    return {
        transform = t,
        grinding = as_bool(grinding),
        balance = as_num(balance),
        stance = as_name(stance),
        grabId = as_name(grab),
        railId = railId,
        splineT = as_num(splineT),
        bail = as_bool(bail),
        _railProp = railName,
    }
end

function M.local_pawn()
    local ok, list = pcall(FindAllOf, "NewMainCharacter_C")
    if ok and list then
        for _, obj in ipairs(list) do
            if obj and obj:IsValid() then
                local isLocal = false
                pcall(function()
                    local pc = obj:GetController() or obj.Controller
                    if pc and pc:IsValid() and pc.IsLocalPlayerController then
                        isLocal = pc:IsLocalPlayerController()
                    elseif pc and pc:IsValid() and pc.Player then
                        isLocal = true
                    end
                end)
                if isLocal then
                    return obj
                end
            end
        end
        for _, obj in ipairs(list) do
            if obj and obj:IsValid() then
                return obj
            end
        end
    end
    local pawn = UEHelpers.GetPlayer()
    if pawn and pawn:IsValid() then
        return pawn
    end
    return nil
end

--- Diff helper used by session to emit reliable grind/trick events.
function M.diff_events(prev, curr)
    local events = {}
    if not curr then
        return events
    end
    prev = prev or {}

    local wasG = not not prev.grinding
    local isG = not not curr.grinding
    if not wasG and isG then
        events[#events + 1] = {
            kind = "grind_enter",
            railId = curr.railId,
            splineT = curr.splineT,
            stance = curr.stance,
            balance = curr.balance,
        }
    elseif wasG and isG then
        local stanceChanged = (prev.stance or "") ~= (curr.stance or "")
        local balChanged = math.abs((prev.balance or 0) - (curr.balance or 0)) > 0.02
        local tChanged = math.abs((prev.splineT or 0) - (curr.splineT or 0)) > 0.001
        if stanceChanged or balChanged or tChanged then
            events[#events + 1] = {
                kind = "grind_update",
                splineT = curr.splineT,
                stance = curr.stance,
                balance = curr.balance,
                lx = 0, ly = 0, rx = 0, ry = 0,
            }
        end
    elseif wasG and not isG then
        local reason = "end"
        if curr.bail then
            reason = "bail"
        end
        events[#events + 1] = {
            kind = "grind_exit",
            reason = reason,
            vx = curr.transform.vx,
            vy = curr.transform.vy,
            vz = curr.transform.vz,
        }
    end

    local prevGrab = prev.grabId or ""
    local currGrab = curr.grabId or ""
    if currGrab ~= "" and currGrab ~= prevGrab then
        events[#events + 1] = { kind = "grab", grabId = currGrab }
    end

    if curr.bail and not prev.bail then
        events[#events + 1] = { kind = "bail" }
    end

    return events
end

return M
