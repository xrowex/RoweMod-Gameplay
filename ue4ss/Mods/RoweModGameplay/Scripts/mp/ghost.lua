--[[
    Remote ghost skaters: spawn a non-possessed copy of NewMainCharacter and
    drive transform + mirrored grind/trick props from network state.
]]

local UEHelpers = require("UEHelpers")

local M = {}

local function log(msg)
    print("[RoweModMP][ghost] " .. tostring(msg))
end

local function set_prop(obj, names, value)
    if not obj or not names then
        return false
    end
    for _, name in ipairs(names) do
        local ok = pcall(function()
            obj[name] = value
        end)
        if ok then
            return true
        end
    end
    return false
end

local function teleport(actor, x, y, z, pitch, yaw, roll)
    pcall(function()
        actor:K2_SetActorLocation({ X = x, Y = y, Z = z }, false, {}, true)
    end)
    pcall(function()
        actor:K2_SetActorRotation({ Pitch = pitch, Yaw = yaw, Roll = roll }, true)
    end)
    -- Older bindings sometimes want FVector userdata from constructors — try alt forms.
    pcall(function()
        if actor.SetActorLocation then
            actor:SetActorLocation(x, y, z, false, true)
        end
    end)
end

local function try_spawn_from_class(class, loc)
    local world = UEHelpers.GetWorld()
    if not world or not world:IsValid() or not class or not class:IsValid() then
        return nil
    end
    local ghost = nil
    pcall(function()
        ghost = world:SpawnActor(class, loc, { Pitch = 0, Yaw = 0, Roll = 0 })
    end)
    if ghost and ghost:IsValid() then
        return ghost
    end
    pcall(function()
        local gs = UEHelpers.GetGameplayStatics and UEHelpers.GetGameplayStatics()
        if gs and gs.BeginDeferredActorSpawnFromClass then
            -- Not all UEHelpers expose this; leave as best-effort.
        end
    end)
    return nil
end

function M.create_manager(propMap)
    local self = {
        ghosts = {}, -- peerId -> { actor, state, displayName }
        propMap = propMap,
    }

    function self:ensure(peerId, displayName)
        local slot = self.ghosts[peerId]
        if slot and slot.actor and slot.actor:IsValid() then
            slot.displayName = displayName or slot.displayName
            return slot
        end
        local localPawn = nil
        pcall(function()
            localPawn = UEHelpers.GetPlayer()
        end)
        local class = nil
        local loc = { X = 0, Y = 0, Z = 200 }
        if localPawn and localPawn:IsValid() then
            pcall(function()
                class = localPawn:GetClass()
                local l = localPawn:K2_GetActorLocation()
                if l then
                    loc = { X = (l.X or 0) + 150, Y = (l.Y or 0) + 150, Z = (l.Z or 0) + 50 }
                end
            end)
        end
        if not class then
            pcall(function()
                class = StaticFindObject("/Game/MainFolder/Character/NewMainCharacter.NewMainCharacter_C")
            end)
        end
        local actor = try_spawn_from_class(class, loc)
        if not actor then
            -- Last resort: CreatePlayer then strip control (splitscreen-style).
            pcall(function()
                local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
                local pcs = FindAllOf("PlayerController")
                local host = pcs and pcs[1]
                if gs and host and host:IsValid() then
                    local pc = gs:CreatePlayer(host, 1, true)
                    if pc and pc:IsValid() and pc.Pawn and pc.Pawn:IsValid() then
                        actor = pc.Pawn
                        pcall(function()
                            pc:UnPossess()
                        end)
                    end
                end
            end)
        end
        if not actor or not actor:IsValid() then
            log("failed to spawn ghost for " .. tostring(peerId))
            return nil
        end
        pcall(function()
            actor:SetActorEnableCollision(false)
        end)
        pcall(function()
            -- Soften physics so remote magnet/balance does not fight teleport.
            if actor.RootComponent and actor.RootComponent.SetSimulatePhysics then
                actor.RootComponent:SetSimulatePhysics(false)
            end
        end)
        slot = {
            actor = actor,
            displayName = displayName or peerId,
            grinding = false,
            stance = "",
            grabId = "",
            last = nil,
        }
        self.ghosts[peerId] = slot
        log("spawned ghost " .. tostring(peerId) .. " -> " .. actor:GetFullName())
        return slot
    end

    function self:apply_transform(peerId, msg)
        local slot = self:ensure(peerId)
        if not slot then
            return
        end
        teleport(slot.actor, msg.x, msg.y, msg.z, msg.pitch, msg.yaw, msg.roll)
        slot.last = msg
    end

    function self:apply_grind_enter(peerId, msg)
        local slot = self:ensure(peerId)
        if not slot then
            return
        end
        slot.grinding = true
        slot.stance = msg.stance or ""
        set_prop(slot.actor, self.propMap.grinding, true)
        set_prop(slot.actor, self.propMap.stance, msg.stance or "")
        set_prop(slot.actor, self.propMap.balance, msg.balance or 0)
        set_prop(slot.actor, self.propMap.splineT, msg.splineT or 0)
        log(string.format("peer %s grind+ rail=%s stance=%s", peerId, tostring(msg.railId), tostring(msg.stance)))
    end

    function self:apply_grind_update(peerId, msg)
        local slot = self.ghosts[peerId]
        if not slot or not slot.actor or not slot.actor:IsValid() then
            return
        end
        slot.stance = msg.stance or slot.stance
        set_prop(slot.actor, self.propMap.stance, msg.stance or "")
        set_prop(slot.actor, self.propMap.balance, msg.balance or 0)
        set_prop(slot.actor, self.propMap.splineT, msg.splineT or 0)
    end

    function self:apply_grind_exit(peerId, msg)
        local slot = self.ghosts[peerId]
        if not slot or not slot.actor or not slot.actor:IsValid() then
            return
        end
        slot.grinding = false
        set_prop(slot.actor, self.propMap.grinding, false)
        log(string.format("peer %s grind- reason=%s", peerId, tostring(msg.reason)))
    end

    function self:apply_grab(peerId, msg)
        local slot = self:ensure(peerId)
        if not slot then
            return
        end
        slot.grabId = msg.grabId or ""
        set_prop(slot.actor, self.propMap.grab, msg.grabId or "")
        log(string.format("peer %s grab=%s", peerId, tostring(msg.grabId)))
    end

    function self:apply_bail(peerId)
        local slot = self.ghosts[peerId]
        if not slot or not slot.actor or not slot.actor:IsValid() then
            return
        end
        set_prop(slot.actor, self.propMap.bail, true)
        log("peer " .. tostring(peerId) .. " bail")
    end

    function self:remove(peerId)
        local slot = self.ghosts[peerId]
        if not slot then
            return
        end
        pcall(function()
            if slot.actor and slot.actor:IsValid() then
                slot.actor:K2_DestroyActor()
            end
        end)
        self.ghosts[peerId] = nil
    end

    function self:clear()
        for peerId, _ in pairs(self.ghosts) do
            self:remove(peerId)
        end
    end

    return self
end

return M
