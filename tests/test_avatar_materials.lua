package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local avatar=require("mp.avatar")
local creates,writes=0,0
function FName(n) return n end
local asset={IsValid=function() return true end,IsA=function() return true end}
function StaticFindObject() return asset end
local component={}
function component:CreateDynamicMaterialInstance()
    creates=creates+1
    return {IsValid=function() return true end,
        SetVectorParameterValue=function(_,name,v) writes=writes+1 end,
        SetScalarParameterValue=function() writes=writes+1 end}
end
local function frame(wind,tint)
    return {1,{{"Upper","static","/Game/Shirt.Shirt",{},
        {{"/Game/Mat.Mat",{},{{"WindDirection",{wind,0,0,1}},{"Tint",{tint,1,1,1}}},{}}}}},
        {{{0,0,0,0,0,0,1,1,1,1},{}}}}
end
local slot={parts={component}}
local a,b=frame(0,1),frame(1,.5)
assert(avatar.geometry_key(a)==avatar.geometry_key(b),"animated material state must not rebuild the avatar")
avatar.update_materials(slot,a)
avatar.update_materials(slot,b)
assert(creates==1 and writes==4,"wind and outfit colors update the existing material")
avatar.update_materials(slot,b)
assert(writes==4,"unchanged materials need no engine calls")
table.remove(b[2][1][5][1][3],1)
avatar.update_materials(slot,b)
assert(creates==2,"removing a parameter recreates only its material to clear stale overrides")
print("animated materials preserve avatar and interpolation buffer")
