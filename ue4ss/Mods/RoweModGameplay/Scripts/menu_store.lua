-- Data-only settings overlay; never execute a saved preset as Lua.
local M = {}
local known = {}
for _, group in ipairs(require("menu_schema")) do
    for _, item in ipairs(group.items) do known[item[1]] = item end
end
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
                if value and value == value and value >= item[3] and value <= item[4] then values[key] = value end
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
    for key in pairs(known) do
        if type(config[key]) == "number" or type(config[key]) == "boolean" then
            rows[#rows + 1] = key .. "=" .. tostring(config[key])
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
