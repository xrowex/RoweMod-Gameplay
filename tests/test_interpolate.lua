package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local m=require("mp.interpolate")
local function frame(x,z,w)
    local t={x,0,0,0,0,z or 0,w or 1,1,1,1}
    return {1,{{"body","skeletal","/Game/Body",{"root"},{}}},{{t,{t}}}}
end
local s={}
m.push(s,frame(0),1)
m.push(s,frame(100),1.1)
local f=m.sample(s,1.17,.12)
assert(math.abs(f[3][1][1][1]-50)<.0001,"intermediate position rather than packet step")
assert(math.abs(f[3][1][2][1][1]-50)<.0001,"bones interpolate too")
assert(m.sample(s,2)[3][1][1][1]==100,"packet loss holds latest pose without runaway")
local angle=math.rad(179)/2
local blended=m.blend(frame(0,math.sin(angle),math.cos(angle)),frame(0,-math.sin(angle),math.cos(angle)),.5)
assert(math.abs(blended[3][1][1][7])<.001,"179 to -179 takes shortest path")
m.push(s,frame(3000),1.2)
assert(#s.samples==1 and m.sample(s,1.2)[3][1][1][1]==3000,"teleports reset buffer")
m.push(s,frame(3010),1.2)
assert(#s.samples==1,"same-poll updates coalesce")
for i=1,30 do m.push(s,frame(3010+i),1.2+i/100) end
assert(#s.samples<=8,"bounded history")
print("pose interpolation, shortest rotation, loss and teleport checks passed")
