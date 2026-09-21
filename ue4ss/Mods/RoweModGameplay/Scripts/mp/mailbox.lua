--[[
    File mailbox IPC between the Lua mod and tools/rowemod_mp.py.
    Layout:
      <dir>/out/<seq>.msg   -- game → bridge
      <dir>/in/<seq>.msg    -- bridge → game
      <dir>/meta.lua.txt    -- optional status from bridge
]]

local M = {}

local function ensure_dir(path)
    -- Best-effort on Windows / Wine; failures are non-fatal.
    pcall(function()
        os.execute(string.format('mkdir "%s" 2>nul', path:gsub("/", "\\")))
    end)
    pcall(function()
        os.execute(string.format('mkdir -p "%s" 2>/dev/null', path))
    end)
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
        inSeen = {},
    }
    ensure_dir(dir)
    ensure_dir(self.outDir)
    ensure_dir(self.inDir)

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
        -- Probe a sliding window of seq files. Bridge uses monotonic seq from 1.
        -- We also try listing via a manifest the bridge maintains.
        local manifestPath = self.inDir .. "/manifest.txt"
        local names = {}
        local mf = io.open(manifestPath, "rb")
        if mf then
            for name in mf:lines() do
                name = name:gsub("%s+", "")
                if name ~= "" then
                    names[#names + 1] = name
                end
            end
            mf:close()
        end
        if #names == 0 then
            -- Blind probe recent seqs if bridge uses numeric names.
            for i = 1, 64 do
                names[#names + 1] = string.format("%06d.msg", i)
            end
        end
        local taken = 0
        for _, name in ipairs(names) do
            if taken >= maxN then
                break
            end
            if not self.inSeen[name] then
                local path = self.inDir .. "/" .. name
                local f = io.open(path, "rb")
                if f then
                    local content = f:read("*a")
                    f:close()
                    self.inSeen[name] = true
                    os.remove(path)
                    if content and content ~= "" then
                        for line in string.gmatch(content, "([^\n]+)") do
                            lines[#lines + 1] = line
                            taken = taken + 1
                        end
                    end
                end
            end
        end
        -- Rewrite manifest without consumed names (best effort).
        if #names > 0 then
            pcall(function()
                local left = {}
                for _, name in ipairs(names) do
                    if not self.inSeen[name] then
                        left[#left + 1] = name
                    end
                end
                local f = io.open(manifestPath, "wb")
                if f then
                    for _, name in ipairs(left) do
                        f:write(name)
                        f:write("\n")
                    end
                    f:close()
                end
            end)
        end
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
