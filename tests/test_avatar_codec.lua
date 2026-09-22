package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local c=require("mp.codec")
local p=require("mp.protocol")
local value={"hat|a%\r\n",{1,-1.25,{}}}
local encoded=c.encode(value)
assert(not encoded:find("\n",1,true))
local decoded=c.decode(encoded)
assert(decoded[1]==value[1] and decoded[2][2]==-1.25)
for _,bad in ipairs({"a9999999:","a1:n1e999;","s4:abc","a1:a1:",encoded.."junk"}) do
    assert(c.decode(bad)==nil,bad)
end
assert(p.decode("F|1|n2;")==nil)
assert(p.decode("F|999999999999999999999999|a0:")==nil)
local f={1,{{"Boot","static","/Game/Boot.Boot",{}, {}}},{{{0,0,0,0,0,0,1,1,1,1},{}}}}
local received=p.decode(p.encode_frame(5,"Park",f))
assert(received.seq==5 and received.mapId=="Park")
require("mp.avatar").validate(received.frame)
print("bounded codec and avatar protocol passed")
