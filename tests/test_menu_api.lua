-- Exercise the actual main.lua boundary and reset path without native UE objects.
package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local function actor(id)
    return {CasualSpeedIncrease=85555, SprintSpeedIncrease=105555,
        GrindMagnetStrength=10000, MinJumpHeight=0.75,
        IsValid=function() return true end, GetAddress=function() return id end,
        GetFullName=function() return "actor"..id end}
end
local pawn,save=actor(1),actor(2)
local world={WorldGravityZ=-1355,bWorldGravitySet=false,GlobalGravityZ=0,bGlobalGravitySet=false,IsValid=function() return true end,GetAddress=function() return 10 end}
pawn.Gravity=1355
local api,timers
timers={}
package.loaded.UEHelpers={GetPlayer=function() return pawn end,GetWorldSettings=function() return world end}
package.loaded.game_thread={wrap=function(fn) return fn end,loop=function(ms,fn) timers[ms]=fn end}
package.loaded["mp.session"]={is_active=function() return false end}
package.loaded["mp.capture"]={local_pawn=function() return pawn end}
package.loaded["mp.online"]={boot=function() end}
package.loaded["auto_update"]={check=function() end}
package.loaded.menu_online={init=function() end}
package.loaded.rowe_menu={init=function(value) api=value end}
package.loaded.menu_store={load=function() return {} end}
package.preload.config=function() return {speedMultiplier=1,mp={enabled=false}} end
Key=setmetatable({}, {__index=function(_,key) return key end})
function RegisterKeyBind() end
function RegisterHook() end
function RegisterConsoleCommandHandler() end
function FindAllOf(name)
    if name=="NewMainCharacter_C" then return {pawn} end
    if name=="SettingsSaveGame_C" then return {save} end
end
dofile("ue4ss/Mods/RoweModGameplay/Scripts/main.lua")
assert(api)
assert(api.get("gravityMultiplier")==1)
timers[4000]() -- snapshot the existing values, including a corrupt old save
assert(api.set("grindMagnetStrength",0.831))
assert(pawn.GrindMagnetStrength==0.85 and save.GrindMagnetStrength==0.85)
assert(not api.set("grindMagnetStrength",math.huge))
assert(not api.set("maxSpinSpeed",999))
api.reset("grindMagnetStrength")
assert(pawn.GrindMagnetStrength==0.8 and save.GrindMagnetStrength==0.8,'Unsafe snapshots must recover to stock')
assert(api.set("minJumpHeight",0.3) and pawn.MinJumpHeight==0.25)
api.reset("minJumpHeight")
assert(pawn.MinJumpHeight==0.75 and save.MinJumpHeight==0.75,'Valid user snapshots must survive Reset')
assert(api.set("speedMultiplier",1.53))
assert(pawn.CasualSpeedIncrease==85555*1.55 and pawn.SprintSpeedIncrease==105555*1.55)
assert(api.set("gravityMultiplier",0.531))
assert(api.get("gravityMultiplier")==0.55 and world.WorldGravityZ==-1355*0.55 and pawn.Gravity==1355*0.55)
api.reset("gravityMultiplier")
assert(world.WorldGravityZ==-1355 and pawn.Gravity==1355 and api.get("gravityMultiplier")==1)
world.WorldGravityZ=0
local value,reason=api.get("gravityMultiplier")
assert(value==nil and reason=="Gravity: waiting for world physics",'Loaded park must not show a missing-park message')
pawn=nil
value,reason=api.get("gravityMultiplier")
assert(value==nil and reason=="Load a park to edit",'Missing local pawn still needs a park')
print("Live API validation, actual acceleration scale, safe reset and user-value preservation passed")
