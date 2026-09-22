-- UE4SS keybinds and async timers must not touch Unreal actors directly.
local M = {}
local actions, pending = {}, {}
local dispatcher

local function drain_actions()
    -- Only this persistent native callback invokes gameplay functions. Keybinds
    -- enqueue data instead of registering a new Lua callback with UE4SS while
    -- the capture/render timers are running.
    local batch = pending
    pending = {}
    local now = os.clock()
    for _, item in ipairs(batch) do
        if item.due > now then
            pending[#pending + 1] = item
        else
            local ok, err = pcall(actions[item.id], table.unpack(item.args, 1, item.args.n))
            if not ok then
                print("[RoweModGameplay] queued action error: " .. tostring(err))
            end
        end
    end
    return false
end

function M.wrap(callback, delay_ms)
    if type(LoopInGameThreadWithDelay) == "function" then
        if not dispatcher then
            dispatcher = LoopInGameThreadWithDelay(16, drain_actions)
        end
        local id = #actions + 1
        actions[id] = callback
        return function(...)
            if #pending >= 128 then return end
            pending[#pending + 1] = {
                id = id, args = table.pack(...),
                due = os.clock() + (delay_ms or 0) / 1000,
            }
        end
    end
    return function(...)
        local args = table.pack(...)
        local function enqueue()
            ExecuteInGameThread(function()
                callback(table.unpack(args, 1, args.n))
            end)
        end
        if delay_ms then ExecuteWithDelay(delay_ms, enqueue) else enqueue() end
    end
end

function M.loop(milliseconds, callback)
    if type(LoopInGameThreadWithDelay) == "function" then
        -- One persistent game-thread timer: no per-tick Lua registry transfers
        -- between the async thread and EngineTick.
        return LoopInGameThreadWithDelay(milliseconds, function()
            local ok, err = pcall(callback)
            if not ok then
                print("[RoweModGameplay] game-thread update error: " .. tostring(err))
            end
            return false
        end)
    end
    local pending = false
    LoopAsync(milliseconds, function()
        -- A paused/busy game must not accumulate actor updates in the queue.
        if not pending then
            pending = true
            local queued, queueError = pcall(ExecuteInGameThread, function()
                local ok, err = pcall(callback)
                pending = false
                if not ok then
                    print("[RoweModGameplay] game-thread update error: " .. tostring(err))
                end
            end)
            if not queued then
                pending = false
                print("[RoweModGameplay] game-thread queue error: " .. tostring(queueError))
            end
        end
        return false
    end)
end

return M
