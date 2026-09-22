package.path = "ue4ss/Mods/RoweModGameplay/Scripts/?.lua;" .. package.path
local pump, registrations, now = nil, 0, 0
os.clock = function() return now end
function LoopInGameThreadWithDelay(ms, callback)
    assert(ms == 16)
    registrations = registrations + 1
    pump = callback
    return 42
end
function ExecuteInGameThread() error("hotkeys must not register transient callbacks") end
function ExecuteWithDelay() error("restart must not register transient callbacks") end
local dispatch = require("game_thread")
local speed, delayed, args = 1.25, 0, nil
local plus = dispatch.wrap(function() speed = speed + 0.1 end)
local minus = dispatch.wrap(function() speed = speed - 0.1 end)
local restart = dispatch.wrap(function() delayed = delayed + 1 end, 800)
local capture = dispatch.wrap(function(...) args = table.pack(...) end)
local bad = dispatch.wrap(function() error("intentional action failure") end)
assert(registrations == 1)
for _ = 1, 25 do plus(); minus() end
restart(); capture("a", nil, "c"); bad(); plus()
assert(speed == 1.25 and delayed == 0 and args == nil)
assert(pump() == false)
assert(math.abs(speed - 1.35) < 0.00001 and delayed == 0)
assert(args.n == 3 and args[1] == "a" and args[3] == "c")
now = 0.81
pump(); pump()
assert(delayed == 1 and registrations == 1)
-- Long key repeat is bounded while the game thread is stalled.
for _ = 1, 1000 do plus() end
local before = speed
pump()
assert(math.abs(speed - before - 12.8) < 0.00001)
print("PASS: persistent hotkey dispatcher, burst limit, delayed restart and error recovery")
