package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local function obj(id,z)
    return {WorldGravityZ=z,bWorldGravitySet=false,GlobalGravityZ=0,bGlobalGravitySet=false,Gravity=1355,
        IsValid=function() return true end,GetAddress=function() return id end}
end
local world,pawn=obj(1,-1355),obj(2)
package.loaded.UEHelpers={GetWorldSettings=function() return world end}
local gravity=require("gravity")
assert(gravity.available())
assert(gravity.apply(nil,{pawn}) and world.WorldGravityZ==-1355)
assert(gravity.apply(0.5,{pawn}))
assert(world.WorldGravityZ==-677.5 and pawn.Gravity==677.5)
assert(world.bGlobalGravitySet and world.GlobalGravityZ==-677.5)
-- Match UE's real GetGravityZ path: a false cache flag recomputes each call.
local function engine_gravity(settings)
    if not settings.bWorldGravitySet then
        settings.WorldGravityZ=settings.bGlobalGravitySet and settings.GlobalGravityZ or -1355
    end
    return settings.WorldGravityZ
end
assert(engine_gravity(world)==-677.5,'Engine must not overwrite the selected gravity')
assert(gravity.apply(0.5,{pawn}) and world.WorldGravityZ==-677.5,'Repeated applies must not compound')
local respawn=obj(3)
assert(gravity.apply(2,{respawn}) and world.WorldGravityZ==-2710 and respawn.Gravity==2710)
assert(gravity.apply(1,{pawn,respawn}) and world.WorldGravityZ==-1355 and pawn.Gravity==1355)
assert(not world.bGlobalGravitySet and world.GlobalGravityZ==0,'Reset restores the original override settings')
assert(gravity.apply(nil,{pawn,respawn}) and respawn.Gravity==1355)
assert(not gravity.apply(0,{pawn}) and not gravity.apply(math.huge,{pawn}))
assert(gravity.apply(0.5,{pawn}))
world=obj(4,-980);local custom=obj(5);custom.Gravity=980
assert(gravity.apply(0.5,{custom}) and world.WorldGravityZ==-490 and custom.Gravity==490,'Travel uses the new map baseline')
assert(gravity.apply(nil,{custom}) and world.WorldGravityZ==-980 and custom.Gravity==980)
world.bWorldGravitySet=false
assert(gravity.available() and gravity.apply(0.5,{custom}),'Cache flag does not indicate whether a park is loaded')
assert(gravity.apply(nil,{custom}))
world=obj(6,0)
assert(not gravity.available() and not gravity.apply(0.5,{custom}))
assert(world.WorldGravityZ==0,'Uninitialized gravity must not be changed')
world=obj(7,-800);world.GlobalGravityZ=-800;world.bGlobalGravitySet=true
assert(gravity.apply(0.5,{custom}) and world.GlobalGravityZ==-400)
assert(gravity.apply(nil,{custom}) and world.bGlobalGravitySet and world.GlobalGravityZ==-800)
world=obj(8,-980);world.bWorldGravitySet=true
assert(gravity.apply(0.5,{custom}) and engine_gravity(world)==-490,'Cached/replicated gravity also updates')
world=nil
assert(not gravity.available() and gravity.apply(nil,{pawn}))
print('Physics gravity, synchronized prediction, repeat apply, reset, respawn and map travel passed')
