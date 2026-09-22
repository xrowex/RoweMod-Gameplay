-- Data-only settings overlay; never execute a saved preset as Lua.
local M = {}
local limits = require("menu_values")
local known = limits.items
function M.path()
    return (os.getenv("LOCALAPPDATA") or os.getenv("TEMP") or "."):gsub("\\", "/") .. "/RoweMod/gameplay-settings.txt"
end
function M.decode(text)
    local values = {}
    if type(text) ~= "string" or #text > 16384 then return values end
    for line in text:gmatch("[^\r\n]+") do
        local key, raw = line:match("^([%w_]+)=(.+)$")
        local item = known[key]
        if item then
            if item[3] == "bool" then
                if raw == "true" then values[key] = true elseif raw == "false" then values[key] = false end
            else
                local value = tonumber(raw)
                if limits.finite(value) then
                    -- Old menus allowed enormous values. Recover to stock, never to
                    -- the new maximum. Keep the original file intact until Save.
                    values[key] = limits.in_range(item,value) and limits.snap(item,value) or item.default
                end
            end
        end
    end
    return values
end
function M.load()
    local f = io.open(M.path(), "rb")
    if not f then return {} end
    local text = f:read(16385); f:close()
    return M.decode(text)
end
function M.save(config)
    local rows = {}
    for key,item in pairs(known) do
        local value=config[key]
        if item[3]=="bool" then
            if type(value)=="boolean" then rows[#rows+1]=key.."="..tostring(value) end
        elseif limits.finite(value) then
            value=limits.in_range(item,value) and limits.snap(item,value) or item.default
            rows[#rows+1]=key.."="..tostring(value)
        end
    end
    table.sort(rows)
    local path = M.path()
    local f, err = io.open(path .. ".tmp", "wb")
    if not f then return false, err end
    local ok = f:write(table.concat(rows, "\n") .. "\n")
    f:close()
    if not ok then return false, "Could not write settings" end
    -- Preserve the last successful save if the final rename fails.
    local existing = io.open(path, "rb")
    if existing then
        existing:close()
        os.remove(path .. ".bak")
        local moved, detail = os.rename(path, path .. ".bak")
        if not moved then return false, detail end
    end
    local moved, detail = os.rename(path .. ".tmp", path)
    if not moved then os.rename(path .. ".bak", path); return false, detail end
    return true
end
return M
