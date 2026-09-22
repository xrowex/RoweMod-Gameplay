--[[
    File mailbox IPC between the Lua mod and tools/rowemod_mp.py.
    Layout:
      <dir>/out/<seq>.msg   -- game → bridge
      <dir>/in/<seq>.msg    -- bridge → game
      <dir>/meta.lua.txt    -- optional status from bridge
]]

local M = {}

local function ensure_dir(path)
    -- The bridge normally creates these directories before the game starts.
    -- Avoid spawning shells on the game thread for directories already present.
    local probe = path .. "/.game-write-check"
    local f = io.open(probe, "wb")
    if f then f:close(); os.remove(probe); return end
    if package.config:sub(1, 1) == "\\" then
        os.execute(string.format('mkdir "%s" 2>nul', path:gsub("/", "\\")))
    else
        os.execute(string.format('mkdir -p "%s"', path))
    end
end

function M.default_dir()
    local tmp = os.getenv("TEMP") or os.getenv("TMP") or os.getenv("TMPDIR") or "."
    return (tmp:gsub("\\", "/") .. "/RoweModMP")
end

--- Resolve mailbox path: explicit arg → env ROUEMOD_MP_MAILBOX → default.
function M.resolve_dir(explicit)
    if type(explicit) == "string" and explicit ~= "" then
        return explicit:gsub("\\", "/")
    end
    local env = os.getenv("ROUEMOD_MP_MAILBOX")
    if type(env) == "string" and env ~= "" then
        return env:gsub("\\", "/")
    end
    return M.default_dir()
end

function M.open(dir)
    dir = M.resolve_dir(dir)
    dir = dir:gsub("\\", "/")
    local self = {
        dir = dir,
        outDir = dir .. "/out",
        inDir = dir .. "/in",
        outSeq = 0,
        manifestOffset = 0,
    }
    ensure_dir(dir)
    ensure_dir(self.outDir)
    ensure_dir(self.inDir)

    -- A new session must not replay an earlier game's poses or spend minutes
    -- walking deleted manifest entries. Bridge heartbeats restore the roster.
    local manifest = io.open(self.inDir .. "/manifest.txt", "rb")
    if manifest then
        self.manifestOffset = manifest:seek("end")
        manifest:close()
    end

    -- Resume out seq from existing files if any.
    pcall(function()
        local maxSeq = 0
        -- No reliable listdir in all UE4SS builds; start from time-based seed.
        maxSeq = math.floor(os.time() % 100000) * 100
        self.outSeq = maxSeq
    end)

    function self:write_line(line)
        self.outSeq = self.outSeq + 1
        local path = string.format("%s/%06d.msg", self.outDir, self.outSeq)
        local tmp = path .. ".tmp"
        local ok, err = pcall(function()
            local f = assert(io.open(tmp, "wb"))
            f:write(line)
            f:write("\n")
            f:close()
            os.remove(path)
            os.rename(tmp, path)
        end)
        if not ok then
            -- Fallback: direct write
            pcall(function()
                local f = assert(io.open(path, "wb"))
                f:write(line)
                f:write("\n")
                f:close()
            end)
        end
        return self.outSeq
    end

    function self:poll_inbox(maxN)
        maxN = maxN or 32
        local lines = {}
        -- The bridge is the sole manifest writer. Truncating it from the game
        -- used to race with append_manifest and permanently lose packets.
        local manifestPath = self.inDir .. "/manifest.txt"
        local mf = io.open(manifestPath, "rb")
        if not mf then return lines end
        local size = mf:seek("end")
        if size < self.manifestOffset then self.manifestOffset = 0 end
        mf:seek("set", self.manifestOffset)
        for _ = 1, maxN do
            local start = mf:seek()
            local name = mf:read("*l")
            if not name then break end
            local nextOffset = mf:seek()
            -- An append may be incomplete; consume only newline-terminated names.
            mf:seek("set", nextOffset - 1)
            local terminator = mf:read(1)
            if terminator ~= "\n" then mf:seek("set", start); break end
            name = name:gsub("\r$", "")
            if name:match("^%d+%.msg$") then
                local path = self.inDir .. "/" .. name
                local f = io.open(path, "rb")
                if f then
                    local content = f:read("*a")
                    f:close()
                    os.remove(path)
                    for line in content:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
                end
            end
            self.manifestOffset = nextOffset
        end
        mf:close()
        return lines
    end

    function self:write_status(text)
        pcall(function()
            local f = assert(io.open(self.dir .. "/game_status.txt", "wb"))
            f:write(tostring(text or ""))
            f:write("\n")
            f:close()
        end)
    end

    function self:read_bridge_status()
        local f = io.open(self.dir .. "/bridge_status.txt", "rb")
        if not f then
            return nil
        end
        local s = f:read("*l")
        f:close()
        return s
    end

    return self
end

return M
