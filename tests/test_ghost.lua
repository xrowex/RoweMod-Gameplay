package.path = "ue4ss/Mods/RoweModGameplay/Scripts/?.lua;" .. package.path
local realAvatar = require("mp.avatar")
local spawned, attempts, clock = 0, 0, 100
local originalTime,originalClock = os.time,os.clock
os.time=function() return clock end
os.clock=function() return clock end
local function frame(x, asset)
    return {1, {{"Body","static",asset or "/Game/Body.Body",{}, {}}},
        {{{x,0,0,0,0,0,1,1,1,1},{}}}}
end
package.loaded["mp.avatar"] = {
    validate=realAvatar.validate,
    geometry_key=realAvatar.geometry_key,
    update_materials=function() end,
    spawn=function(f)
        attempts=attempts+1
        if f[2][1][3]=="/Game/Missing.Missing" then error("missing shared asset") end
        spawned=spawned+1
        local actor={alive=true}
        function actor:IsValid() return self.alive end
        function actor:K2_DestroyActor() self.alive=false end
        return {actor=actor,parts={true},x=f[3][1][1][1]}
    end,
    apply=function(s,f) if s.fail then error("broken remote component") end;s.x=f[3][1][1][1] end,
}
local m=require("mp.ghost").create_manager()
m:ensure("A","same name"); assert(spawned==0)
assert(m:apply_frame("A",{seq=2,frame=frame(10)}))
assert(m:apply_frame("B",{seq=2,frame=frame(20)}))
local a,b=m.ghosts.A,m.ghosts.B
assert(a~=b and a.x==10 and b.x==20)
assert(not m:apply_frame("A",{seq=1,frame=frame(999)}))
clock=100.1
assert(m:apply_frame("A",{seq=3,frame=frame(30)}))
m:render(100.22)
assert(a.x==30 and b.x==20 and spawned==2,"only the sender moves")
assert(m:apply_frame("A",{seq=4,frame=frame(30,"/Game/Shirt.Shirt")}))
assert(not a.actor.alive and b.actor.alive and spawned==3,"outfit replaces only sender")
local bad=frame(40); bad[3][1][1][7]=0
assert(not pcall(m.apply_frame,m,"B",{seq=3,frame=bad}))
assert(spawned==3 and m.lastSeq.B==2,"invalid pose never reaches engine")
assert(not pcall(m.apply_frame,m,"C",{seq=1,frame=frame(0,"/Game/Missing.Missing")}))
local before=attempts
assert(not m:apply_frame("C",{seq=2,frame=frame(0,"/Game/Missing.Missing")}))
assert(attempts==before,"missing assets must not spawn every frame")
clock=104
assert(m:apply_frame("C",{seq=3,frame=frame(40)}))
m:remove("B")
assert(not b.actor.alive and m:apply_frame("B",{seq=1,frame=frame(50)}),"reconnect resets sequence")
m.ghosts.A.fail=true
clock=105
m:apply_frame('A',{seq=5,frame=frame(60,'/Game/Shirt.Shirt')})
m:apply_frame('B',{seq=2,frame=frame(70)})
m:render(105.2)
assert(m.ghosts.A.renderError and m.ghosts.B.x==70,'One broken avatar must not stop other avatars rendering')
m.ghosts.A.fail=false;m:render(105.3)
assert(not m.ghosts.A.renderError and m.ghosts.A.lastRendered==105,'Render failure can recover')
m:clear()
assert(next(m.ghosts)==nil and next(m.lastSeq)==nil and next(m.retryAfter)==nil)
os.time,os.clock=originalTime,originalClock
print("remote ownership, appearance replacement, validation, retry and reconnect passed")
