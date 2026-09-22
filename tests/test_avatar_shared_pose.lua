package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
function FName(s) return s end
local avatar=require("mp.avatar")
local calls,links=0,0
local function component()
    return {K2_SetWorldTransform=function() end,
        SetLeaderPoseComponent=function(self,leader) self.leader=leader;links=links+1 end,
        SetBoneTransformByName=function(self)
            assert(not self.leader,"engine forbids setting bones on a follower")
            calls=calls+1
        end}
end
local function t(x) return {x,0,0,0,0,0,1,1,1,1} end
local appearance={
    {"Body","skeletal","/Game/Body",{"root"},{}},
    {"Boots","skeletal","/Game/Boots",{"root"},{}},
    {"Shirt","skeletal","/Game/Shirt",{"root"},{}},
    {"Pants","skeletal","/Game/Pants",{"root"},{}}}
local frame={1,appearance,{{t(0),{t(1)}},{t(2),{t(1)}},{t(3),{t(1)}},{t(4),{t(1)}}}}
local slot={appearance=appearance,parts={component(),component(),component(),component()}}
avatar.apply(slot,frame)
assert(calls==1 and links==3 and slot.sharedParts==3,"four meshes use one skeleton update")
avatar.apply(slot,frame)
assert(calls==2 and links==3,"stable sharing must not rebuild engine links")
frame[3][2][2][1]=t(2)
avatar.apply(slot,frame)
assert(calls==4 and links==4 and not slot.parts[2].leader,"different boot pose detaches before bone writes")
frame[3][2][2][1]=t(1)
avatar.apply(slot,frame)
assert(calls==5 and links==5 and slot.sharedParts==3,"matching pose can rejoin")
print("shared pose reduces four skeletal updates to one and preserves independent poses")
