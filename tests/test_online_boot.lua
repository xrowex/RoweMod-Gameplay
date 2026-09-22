package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local online=require("mp.online")
assert(online.lobby_argument("Game.exe +connect_lobby 12345 -windowed")=="12345")
assert(not online.lobby_argument("+connect_lobby 12&start"))
assert(not online.lobby_argument("+connect_lobby -12"))
assert(not online.lobby_argument("+connect_lobby 123456789012345678901"))
local invoked=false
os.execute=function() invoked=true end
assert(not online.open("123&whoami"))
assert(not invoked)
local cfg={}
online.configure(cfg)
assert(cfg.mp.online and cfg.mp.enabled and cfg.mp.role=="auto")
assert(cfg.mp.mailboxDir:match("/Steam$"))
print("online launch argument and mailbox tests passed")
