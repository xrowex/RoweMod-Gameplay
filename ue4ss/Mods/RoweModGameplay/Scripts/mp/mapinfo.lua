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
    -- UEDPIE_0_MapName → MapName
    s = s:gsub("^UEDPIE_%d+_", "")
    -- package path /Game/Foo/Bar.Bar → Bar (prefer asset name)
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
    for _, c in ipairs(candidates) do
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

--- Best-effort travel to a map short name or /Game/... path.
--- Returns ok, detail.
function M.travel(mapId)
    mapId = trim(mapId)
    if mapId == "" or mapId == "unknown" then
        return false, "no map id"
    end
    local world = UEHelpers.GetWorld()
    if not world or not world:IsValid() then
        return false, "no world"
    end

    local attempts = { mapId }
    -- If it looks like a short name, also try common Rollout content roots.
    if not mapId:find("/", 1, true) then
        attempts[#attempts + 1] = "/Game/MainFolder/Maps/" .. mapId
        attempts[#attempts + 1] = "/Game/MainFolder/" .. mapId
        attempts[#attempts + 1] = "/Game/Maps/" .. mapId
        attempts[#attempts + 1] = "/Game/" .. mapId
    end

    local gs = nil
    pcall(function()
        gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    end)

    for _, target in ipairs(attempts) do
        local ok = false
        local err = nil
        if gs and gs:IsValid() and gs.OpenLevel then
            ok, err = pcall(function()
                -- OpenLevel(WorldContextObject, LevelName, bAbsolute, Options)
                gs:OpenLevel(world, target, true, "")
            end)
        end
        if ok then
            return true, "OpenLevel " .. target
        end
        -- Console fallback
        local ok2 = pcall(function()
            local pc = UEHelpers.GetPlayerController and UEHelpers.GetPlayerController()
            if pc and pc:IsValid() and pc.ConsoleCommand then
                pc:ConsoleCommand("open " .. target, true)
            elseif pc and pc:IsValid() and pc.ServerExec then
                pc:ServerExec("open " .. target)
            else
                error("no console")
            end
        end)
        if ok2 then
            return true, "console open " .. target
        end
        if err then
            -- keep trying
        end
    end
    return false, "travel failed for " .. mapId
end

return M
