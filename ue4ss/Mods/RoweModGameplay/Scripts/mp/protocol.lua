--[[
    RoweMod MP wire format — line-oriented, no JSON dependency.

    T|seq|x|y|z|pitch|yaw|roll|vx|vy|vz
    G+|seq|railId|splineT|stance|balance
    G*|seq|splineT|stance|balance|lx|ly|rx|ry
    G-|seq|reason|vx|vy|vz
    A|seq|grabId
    B|seq
    L|seq|ok|stance
    H|seq|name|ver|mapId          -- hello (v2 includes map)
    M|seq|mapId                    -- local map changed / announce
    MREQ|seq|mapId                 -- host asks peers to travel here
    MACK|seq|mapId|ok              -- peer ack travel / current map
    Bye|seq
]]

local M = {}

M.VERSION = "2"

local function num(v, fallback)
    local n = tonumber(v)
    if n == nil then
        return fallback or 0
    end
    return n
end

local function esc(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub("|", "\\p")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "")
    return s
end

local function unesc(s)
    s = tostring(s or "")
    s = s:gsub("\\n", "\n")
    s = s:gsub("\\p", "|")
    s = s:gsub("\\\\", "\\")
    return s
end

local function split_pipe(line)
    local parts = {}
    local buf = ""
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == "\\" and i < #line then
            buf = buf .. line:sub(i, i + 1)
            i = i + 2
        elseif c == "|" then
            parts[#parts + 1] = buf
            buf = ""
            i = i + 1
        else
            buf = buf .. c
            i = i + 1
        end
    end
    parts[#parts + 1] = buf
    return parts
end

function M.encode_transform(seq, t)
    return string.format(
        "T|%d|%.4f|%.4f|%.4f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f",
        seq,
        t.x or 0, t.y or 0, t.z or 0,
        t.pitch or 0, t.yaw or 0, t.roll or 0,
        t.vx or 0, t.vy or 0, t.vz or 0
    )
end

function M.encode_grind_enter(seq, g)
    return string.format(
        "G+|%d|%s|%.4f|%s|%.4f",
        seq,
        esc(g.railId or ""),
        g.splineT or 0,
        esc(g.stance or ""),
        g.balance or 0
    )
end

function M.encode_grind_update(seq, g)
    return string.format(
        "G*|%d|%.4f|%s|%.4f|%.3f|%.3f|%.3f|%.3f",
        seq,
        g.splineT or 0,
        esc(g.stance or ""),
        g.balance or 0,
        g.lx or 0, g.ly or 0, g.rx or 0, g.ry or 0
    )
end

function M.encode_grind_exit(seq, g)
    return string.format(
        "G-|%d|%s|%.3f|%.3f|%.3f",
        seq,
        esc(g.reason or "end"),
        g.vx or 0, g.vy or 0, g.vz or 0
    )
end

function M.encode_grab(seq, grabId)
    return string.format("A|%d|%s", seq, esc(grabId or ""))
end

function M.encode_bail(seq)
    return string.format("B|%d", seq)
end

function M.encode_land(seq, ok, stance)
    return string.format("L|%d|%d|%s", seq, ok and 1 or 0, esc(stance or ""))
end

function M.encode_hello(seq, name, mapId)
    return string.format(
        "H|%d|%s|%s|%s",
        seq,
        esc(name or "skater"),
        esc(M.VERSION),
        esc(mapId or "unknown")
    )
end

function M.encode_map(seq, mapId)
    return string.format("M|%d|%s", seq, esc(mapId or "unknown"))
end

function M.encode_map_req(seq, mapId)
    return string.format("MREQ|%d|%s", seq, esc(mapId or "unknown"))
end

function M.encode_map_ack(seq, mapId, ok)
    return string.format("MACK|%d|%s|%d", seq, esc(mapId or "unknown"), ok and 1 or 0)
end

function M.encode_bye(seq)
    return string.format("Bye|%d", seq)
end

function M.decode(line)
    if type(line) ~= "string" or line == "" then
        return nil
    end
    line = line:gsub("\r", ""):gsub("\n", "")
    local p = split_pipe(line)
    local kind = p[1]
    if not kind then
        return nil
    end
    if kind == "T" then
        return {
            type = "transform",
            seq = num(p[2]),
            x = num(p[3]), y = num(p[4]), z = num(p[5]),
            pitch = num(p[6]), yaw = num(p[7]), roll = num(p[8]),
            vx = num(p[9]), vy = num(p[10]), vz = num(p[11]),
        }
    elseif kind == "G+" then
        return {
            type = "grind_enter",
            seq = num(p[2]),
            railId = unesc(p[3]),
            splineT = num(p[4]),
            stance = unesc(p[5]),
            balance = num(p[6]),
        }
    elseif kind == "G*" then
        return {
            type = "grind_update",
            seq = num(p[2]),
            splineT = num(p[3]),
            stance = unesc(p[4]),
            balance = num(p[5]),
            lx = num(p[6]), ly = num(p[7]), rx = num(p[8]), ry = num(p[9]),
        }
    elseif kind == "G-" then
        return {
            type = "grind_exit",
            seq = num(p[2]),
            reason = unesc(p[3]),
            vx = num(p[4]), vy = num(p[5]), vz = num(p[6]),
        }
    elseif kind == "A" then
        return { type = "grab", seq = num(p[2]), grabId = unesc(p[3]) }
    elseif kind == "B" then
        return { type = "bail", seq = num(p[2]) }
    elseif kind == "L" then
        return { type = "land", seq = num(p[2]), ok = num(p[3]) == 1, stance = unesc(p[4]) }
    elseif kind == "H" then
        return {
            type = "hello",
            seq = num(p[2]),
            name = unesc(p[3]),
            ver = unesc(p[4]),
            mapId = unesc(p[5] or "unknown"),
        }
    elseif kind == "M" then
        return { type = "map", seq = num(p[2]), mapId = unesc(p[3]) }
    elseif kind == "MREQ" then
        return { type = "map_req", seq = num(p[2]), mapId = unesc(p[3]) }
    elseif kind == "MACK" then
        return { type = "map_ack", seq = num(p[2]), mapId = unesc(p[3]), ok = num(p[4]) == 1 }
    elseif kind == "Bye" then
        return { type = "bye", seq = num(p[2]) }
    end
    return nil
end

return M
