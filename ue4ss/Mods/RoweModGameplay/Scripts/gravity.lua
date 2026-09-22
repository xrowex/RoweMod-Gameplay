-- WorldGravityZ is the initialized physics gravity cache in AWorldSettings.
-- The character's positive Gravity field is only used for jump prediction.
local M = {}
local helpers = require("UEHelpers")
local limits = require("menu_values")
local state
local function world_settings()
    local ok,settings=pcall(helpers.GetWorldSettings)
    if not ok or not settings or not settings:IsValid() then return nil end
    local readable,z,initialized=pcall(function() return settings.WorldGravityZ,settings.bWorldGravitySet end)
    if not readable or not initialized or not limits.finite(z) or z>=0 then return nil end
    return settings
end
function M.available() return world_settings()~=nil end
function M.apply(multiplier,pawns)
    if multiplier~=nil then
        local item=limits.items.gravityMultiplier
        if not limits.in_range(item,multiplier) then return false,"Invalid gravity multiplier" end
    end
    local settings=world_settings()
    if not settings then return multiplier==nil,"Gravity is unavailable until this map's physics are ready" end
    local id=settings:GetAddress()
    if state and state.id~=id then state=nil end
    -- A nil override never changes a map we have not edited.
    if not state and multiplier==nil then return true end
    if not state then state={id=id,base=settings.WorldGravityZ,pawns={}} end
    local target=state.base*(multiplier or 1)
    local ok,err=pcall(function()
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
