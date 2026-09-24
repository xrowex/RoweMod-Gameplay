-- bWorldGravitySet is a cache/replication flag, not a physics-ready flag.
-- GetGravityZ can recalculate WorldGravityZ while that flag is false, so
-- keep the world override and its cache in sync instead of editing only cache.
-- The character's positive Gravity field is only used for jump prediction.
local M = {}
local helpers = require("UEHelpers")
local limits = require("menu_values")
local state
local function world_settings()
    local ok,settings=pcall(helpers.GetWorldSettings)
    if not ok or not settings or not settings:IsValid() then return nil,"Gravity: world settings unavailable" end
    local readable,z,global,override=pcall(function()
        return settings.WorldGravityZ,settings.GlobalGravityZ,settings.bGlobalGravitySet
    end)
    if not readable or not limits.finite(global) or type(override)~="boolean" then
        return nil,"Gravity: world settings unreadable"
    end
    local effective=override and global or z
    if not limits.finite(effective) or effective>=0 then return nil,"Gravity: waiting for world physics" end
    return settings,nil,effective,global,override
end
function M.available()
    local settings,reason=world_settings()
    return settings~=nil,reason
end
function M.apply(multiplier,pawns)
    if multiplier~=nil then
        local item=limits.items.gravityMultiplier
        if not limits.in_range(item,multiplier) then return false,"Invalid gravity multiplier" end
    end
    local settings,reason,base,global,override=world_settings()
    if not settings then state=nil;return multiplier==nil,reason end
    local id=settings:GetAddress()
    if state and state.id~=id then state=nil end
    -- A nil override never changes a map we have not edited.
    if not state and multiplier==nil then return true end
    if not state then state={id=id,base=base,global=global,override=override,pawns={}} end
    local target=state.base*(multiplier or 1)
    local reset=multiplier==nil or multiplier==1
    local ok,err=pcall(function()
        local desiredGlobal=reset and state.global or target
        local desiredOverride=not reset or state.override
        if settings.GlobalGravityZ~=desiredGlobal then settings.GlobalGravityZ=desiredGlobal end
        if settings.bGlobalGravitySet~=desiredOverride then settings.bGlobalGravitySet=desiredOverride end
        if settings.WorldGravityZ~=target then settings.WorldGravityZ=target end
    end)
    if not ok then return false,tostring(err) end
    for _,pawn in ipairs(pawns or {}) do
        if pawn and pawn:IsValid() then
            local key=pawn:GetAddress()
            local readable,value=pcall(function() return pawn.Gravity end)
            if readable and limits.finite(value) then
                local original=state.pawns[key]
                if original==nil then original=value;state.pawns[key]=original end
                local predicted=(multiplier==nil or multiplier==1) and original or -target
                local written,detail=pcall(function() if pawn.Gravity~=predicted then pawn.Gravity=predicted end end)
                if not written then return false,tostring(detail) end
            end
        end
    end
    if multiplier==nil then state=nil end
    return true
end
return M
