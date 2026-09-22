--[[
    Detect / normalize the current Unreal map so peers can agree on a world.
]]

local UEHelpers = require("UEHelpers")

local M = {}

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Strip PIE / streaming suffixes into a stable short id.
function M.normalize(raw)
    local s = trim(raw)
    if s == "" then
        return "unknown"
    end
    s = s:gsub("\\", "/")
    -- UEDPIE_0_MapName â†’ MapName
    s = s:gsub("^UEDPIE_%d+_", "")
    -- package path /Game/Foo/Bar.Bar â†’ Bar (prefer asset name)
    local short = s:match("/([^/]+)$")
    if short then
        short = short:gsub("%..*$", "")
        if short ~= "" then
            s = short
        end
    end
    s = s:gsub("%.umap$", ""):gsub("%.$", "")
    return s
end

local function try_gameplay_statics_level_name()
    local name = nil
    pcall(function()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local world = UEHelpers.GetWorld()
        if gs and gs:IsValid() and world and world:IsValid() then
            -- GetCurrentLevelName(WorldContext, bRemovePrefixString)
            if gs.GetCurrentLevelName then
                name = gs:GetCurrentLevelName(world, true)
            end
        end
    end)
    if type(name) == "string" and name ~= "" then
        return name
    end
    if name and name.ToString then
        local ok, s = pcall(function()
            return name:ToString()
        end)
        if ok then
            return s
        end
    end
    return nil
end

local function try_world_name()
    local world = UEHelpers.GetWorld()
    if not world or not world:IsValid() then
        return nil
    end
    local ok, name = pcall(function()
        return world:GetName()
    end)
    if ok and name and name ~= "" then
        return name
    end
    return nil
end

local function try_persistent_package()
    local world = UEHelpers.GetWorld()
    if not world or not world:IsValid() then
        return nil
    end
    local ok, path = pcall(function()
        local level = world.PersistentLevel
        if level and level:IsValid() then
            local outer = level:GetOuter()
            if outer and outer:IsValid() then
                return outer:GetFullName()
            end
            return level:GetFullName()
        end
        return nil
    end)
    if ok and path then
        return path
    end
    return nil
end

local function try_map_name_property()
    local world = UEHelpers.GetWorld()
    if not world or not world:IsValid() then
        return nil
    end
    for _, key in ipairs({ "MapName", "CurrentMap", "LevelName" }) do
        local ok, value = pcall(function()
            return world[key]
        end)
        if ok and value ~= nil then
            if type(value) == "string" then
                return value
            end
            local ok2, s = pcall(function()
                if value.ToString then
                    return value:ToString()
                end
                return tostring(value)
            end)
            if ok2 and s and s ~= "" then
                return s
            end
        end
    end
    return nil
end

--- Returns mapId (normalized), raw candidates, and display label.
function M.current()
    local candidates = {
        try_gameplay_statics_level_name(),
        try_map_name_property(),
        try_world_name(),
        try_persistent_package(),
    }
    local raw = nil
    for i=1,4 do
        local c=candidates[i]
        if c and tostring(c) ~= "" then
            raw = tostring(c)
            break
        end
    end
    local id = M.normalize(raw or "unknown")
    return {
        id = id,
        raw = raw or "",
        label = id,
        candidates = candidates,
    }
end

function M.same(a, b)
    return M.normalize(a) == M.normalize(b)
end

-- Exact stock park packages verified from the installed IoStore directory.
local parks={OutdoorSkatepark="/Game/MainFolder/Maps/OutdoorSkatepark/OutdoorSkatepark",
    TheBigHall="/Game/MainFolder/Maps/TheBigHall/TheBigHall",
    Observatory="/Game/MainFolder/Maps/Observatory/Observatory"}
function M.destination(mapId) return parks[M.normalize(mapId)] end
function M.is_menu(mapId)
    local id=M.normalize(mapId)
    return id=="unknown" or id=="StartMenu" or id=="Entry"
end
-- Request one verified package. Session confirms actual arrival separately.
function M.travel(mapId)
    local target=M.destination(mapId)
    if not target then return false,"This map is not supported for automatic loading: "..M.normalize(mapId) end
    local world=UEHelpers.GetWorld()
    if not world or not world:IsValid() then return false,"No game world is ready" end
    local gs=StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not gs or not gs:IsValid() then return false,"Map loading is unavailable" end
    local ok,err=pcall(function()
        local menu=package.loaded.rowe_menu
        if menu and menu.is_open() then menu.close() end
        gs:OpenLevel(world,FName(target),true,"")
    end)
    return ok,ok and ("Loading "..M.normalize(mapId)) or tostring(err)
end
return M
