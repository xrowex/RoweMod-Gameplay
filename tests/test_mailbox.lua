package.path = "ue4ss/Mods/RoweModGameplay/Scripts/?.lua;" .. package.path
local root = assert(arg[1], "pass an empty temporary directory with in/out folders")
local function write(path, content, mode)
    local f = assert(io.open(path, mode or "wb")); f:write(content); f:close()
end
local manifest = root .. "/in/manifest.txt"
local box = require("mp.mailbox").open(root)
write(root .. "/in/000001.msg", "@peer|first\n")
write(manifest, "000001.msg\n")
-- Append from the bridge while the game is consuming a message.
local remove = os.remove
os.remove = function(path)
    if path:match("000001.msg$") then
        write(root .. "/in/000002.msg", "@peer|second\n")
        write(manifest, "000002.msg\n", "ab")
    end
    return remove(path)
end
assert(box:poll_inbox(1)[1] == "@peer|first")
os.remove = remove
assert(box:poll_inbox(1)[1] == "@peer|second", "concurrent append must survive polling")
assert(#box:poll_inbox(1) == 0, "must not replay consumed messages")
write(root .. "/in/000003.msg", "@peer|third\n")
write(manifest, "000003.m", "ab")
assert(#box:poll_inbox(1) == 0, "partial append must remain pending")
write(manifest, "sg\n", "ab")
assert(box:poll_inbox(1)[1] == "@peer|third")
write(root .. "/in/000004.msg", "@peer|stale\n")
write(manifest, "000004.msg\n", "ab")
box = require("mp.mailbox").open(root)
assert(#box:poll_inbox(48)==0,"restart skips prior session history")
write(root .. "/in/000005.msg", "@peer|fresh\n")
write(manifest, "000005.msg\n", "ab")
assert(box:poll_inbox(1)[1]=="@peer|fresh","new heartbeat/frame delivered immediately")
print("mailbox concurrent append and partial record checks passed")
