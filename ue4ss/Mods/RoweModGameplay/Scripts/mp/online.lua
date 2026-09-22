-- Steam companion bootstrap. Never interpolate raw launch arguments into a shell.
local M = {}

function M.lobby_argument(command)
    local id = (" " .. tostring(command or "") .. " "):match("%s%+connect_lobby%s+(%d+)%s")
    if id and #id <= 20 and id:match("[1-9]") and
        (#id < 20 or id <= "18446744073709551615") then return id end
end

function M.configure(cfg)
    cfg.mp = cfg.mp or {}
    cfg.mp.online = true
    cfg.mp.enabled = true
    cfg.mp.role = "auto"
    cfg.mp.autoTravelToHostMap = true
    cfg.mp.hostMapAuthority = true
    cfg.mp.requireSameMap = true
    local inherited = os.getenv("ROUEMOD_MP_ONLINE") == "1" and os.getenv("ROUEMOD_MP_MAILBOX")
    cfg.mp.mailboxDir = inherited or (require("mp.mailbox").default_dir() .. "/Steam")
end

function M.open(lobby, background)
    if lobby and (not tostring(lobby):match("^%d+$") or #tostring(lobby) > 20) then
        return false, "invalid lobby ID"
    end
    for _, path in ipairs({"RoweModOnline/start_online.vbs", "../RoweModOnline/start_online.vbs"}) do
        local f = io.open(path, "rb")
        if f then
            f:close()
            local argument = lobby and (" +connect_lobby " .. lobby) or ""
            if background then argument = argument .. " --background" end
            local started=os.execute('start "" /B wscript.exe "' .. path .. '"' .. argument)
            if not started then return false,"Could not launch RoweMod Online. Open START ONLINE.cmd for details." end
            return true
        end
    end
    return false, "Online companion missing; run the updated install.ps1"
end

function M.boot(cfg)
    if os.getenv("ROUEMOD_MP_ONLINE") == "1" then M.configure(cfg); return true end
    local ok, command = pcall(function()
        local value = require("UEHelpers").GetKismetSystemLibrary():GetCommandLine()
        if type(value) == "string" then return value end
        return value:ToString()
    end)
    local lobby = ok and M.lobby_argument(command)
    if lobby then
        local started = M.open(lobby)
        if started then M.configure(cfg); return true end
    end
    return false
end

return M
