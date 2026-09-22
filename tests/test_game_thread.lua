-- Run with Lua 5.4 from the repo root: lua tests/test_game_thread.lua
package.path = "ue4ss/Mods/RoweModGameplay/Scripts/?.lua;" .. package.path

local queue, timers, keys = {}, {}, {}
local inGameThread = false
function ExecuteInGameThread(callback)
    queue[#queue + 1] = callback
end
function LoopAsync(interval, callback)
    timers[interval] = callback
end
local function drain()
    local current = queue
    queue = {}
    inGameThread = true
    for _, callback in ipairs(current) do callback() end
    inGameThread = false
end

local dispatch = require("game_thread")
local received
dispatch.wrap(function(...)
    assert(inGameThread)
    received = table.pack(...)
end)("first", nil, "third")
assert(received == nil)
drain()
assert(received.n == 3 and received[1] == "first" and received[3] == "third")

local runs = 0
dispatch.loop(7, function()
    assert(inGameThread)
    runs = runs + 1
    if runs == 1 then error("intentional test error") end
end)
for _ = 1, 100 do assert(timers[7]() == false) end
assert(#queue == 1 and runs == 0, "busy game must coalesce pending updates")
drain()
timers[7]()
drain()
assert(runs == 2, "callback error must not disable later updates")
local enqueue = ExecuteInGameThread
ExecuteInGameThread = function() error("intentional enqueue error") end
timers[7]()
ExecuteInGameThread = enqueue
timers[7]()
drain()
assert(runs == 3, "queue error must allow retry")

-- Exercise actual main.lua registrations, including F9 and the 50 ms MP loop.
local active, starts, stops, ticks = false, 0, 0, 0
package.loaded["UEHelpers"] = {}
package.loaded["mp.session"] = {
    is_active = function() return active end,
    start = function()
        assert(inGameThread, "session start must run on game thread")
        active, starts = true, starts + 1
    end,
    stop = function()
        assert(inGameThread, "ghost cleanup must run on game thread")
        active, stops = false, stops + 1
    end,
    tick = function()
        assert(inGameThread, "ghost spawn/update must run on game thread")
        ticks = ticks + 1
    end,
}
package.preload["config"] = function()
    return { speedMultiplier = 1, mp = { enabled = false, role = "host" } }
end
Key = setmetatable({}, { __index = function(_, key) return key end })
function RegisterKeyBind(key, callback) keys[key] = callback end
function RegisterHook() end
function RegisterConsoleCommandHandler() end
dofile("ue4ss/Mods/RoweModGameplay/Scripts/main.lua")
drain()
keys.F9()
assert(starts == 0)
drain()
assert(starts == 1)
for _ = 1, 100 do timers[50]() end
assert(ticks == 0 and #queue == 1)
drain()
assert(ticks == 1)
keys.F9()
timers[50]() -- queued tick must notice that F9 stopped the session first
drain()
assert(stops == 1 and ticks == 1)
print("PASS: deferred keys/start/stop/tick, coalescing, and error recovery")

local nativeCallback
function LoopInGameThreadWithDelay(interval, callback)
    assert(interval == 50)
    nativeCallback = callback
    return 123
end
LoopAsync = function() error("native timer must not create an async loop") end
local nativeRuns = 0
assert(dispatch.loop(50, function() nativeRuns = nativeRuns + 1 end) == 123)
nativeCallback()
nativeCallback()
assert(nativeRuns == 2)
print("PASS: persistent native timer used when available")
