-- Sender-owned appearance and pose. Engine access must stay on the game thread.
local M = {}
local codec = require("mp.codec")
local function valid(o) return o and o:IsValid() end
local function path(o)
    if not valid(o) then return "" end
    return o:GetFullName():match("^[^ ]+ (.+)$") or ""
end
local function each(a, fn)
    if type(a) == "table" then
        for _, v in ipairs(a) do fn(v:get()) end
    else a:ForEach(function(_, v) fn(v:get()) end) end
end
local function transform(t)
    return {t.Translation.X,t.Translation.Y,t.Translation.Z,
        t.Rotation.X,t.Rotation.Y,t.Rotation.Z,t.Rotation.W,
        t.Scale3D.X,t.Scale3D.Y,t.Scale3D.Z}
end
local captureRigs, rigCount = {}, 0
local function capture_rig(c, meshPath)
    local rig=captureRigs[meshPath]
    if rig then return rig end
    local count=c:GetNumBones()
    assert(count<=256,"avatar rig exceeds 256 bones")
    rig={names={},handles={}}
    for i=0,count-1 do
        local name=c:GetBoneName(i):ToString()
        rig.names[#rig.names+1]=name
        rig.handles[#rig.handles+1]=FName(name)
    end
    if rigCount>=64 then captureRigs={};rigCount=0 end
    captureRigs[meshPath]=rig;rigCount=rigCount+1
    return rig
end
function M.engine_transform(t)
    return {Translation={X=t[1],Y=t[2],Z=t[3]},
        Rotation={X=t[4],Y=t[5],Z=t[6],W=t[7]},Scale3D={X=t[8],Y=t[9],Z=t[10]}}
end
local function material(mat)
    local parent = mat
    if valid(mat.Parent) then parent = mat.Parent end
    local result = {path(parent),{}, {}, {}}
    if valid(mat.Parent) then
        each(mat.ScalarParameterValues, function(p)
            result[2][#result[2]+1] = {p.ParameterInfo.Name:ToString(),p.ParameterValue}
        end)
        each(mat.VectorParameterValues, function(p)
            local c = p.ParameterValue
            result[3][#result[3]+1] = {p.ParameterInfo.Name:ToString(),{c.R,c.G,c.B,c.A}}
        end)
        each(mat.TextureParameterValues, function(p)
            result[4][#result[4]+1] = {p.ParameterInfo.Name:ToString(),path(p.ParameterValue)}
        end)
    end
    return result
end
function M.capture(pawn)
    local appearance, poses = {}, {}
    each(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.MeshComponent")),function(c)
        if not c.bVisible or c.bHiddenInGame then return end
        local mesh, kind = c.StaticMesh, "static"
        if valid(c.SkeletalMesh) then mesh,kind = c.SkeletalMesh,"skeletal" end
        if not valid(mesh) then return end
        local meshPath=path(mesh)
        local bones, bonePose, mats = {}, {}, {}
        if kind == "skeletal" then
            local rig=capture_rig(c,meshPath)
            bones=rig.names
            for _,name in ipairs(rig.handles) do
                bonePose[#bonePose+1] = transform(c:GetSocketTransform(name,2))
            end
        end
        for i=0,c:GetNumMaterials()-1 do mats[#mats+1] = material(c:GetMaterial(i)) end
        appearance[#appearance+1] = {c:GetFName():ToString(),kind,meshPath,bones,mats}
        poses[#poses+1] = {transform(c:K2_GetComponentToWorld()),bonePose}
    end)
    assert(#appearance > 0 and #appearance <= 24,"invalid avatar component count")
    return {1,appearance,poses}
end
local function asset(p, class)
    assert(type(p)=="string" and #p<512 and (p:match("^/Game/") or p:match("^/Engine/"))
        and not p:find(":",1,true),"invalid avatar asset path")
    local o = StaticFindObject(p)
    if not valid(o) then LoadAsset(p); o = StaticFindObject(p) end
    assert(valid(o),"missing shared asset: "..p)
    assert(o:IsA(StaticFindObject("/Script/Engine."..class)),"wrong avatar asset type: "..p)
    return o
end
local identity = {0,0,0,0,0,0,1,1,1,1}
function M.geometry_key(frame)
    local shape={}
    for i,p in ipairs(frame[2]) do shape[i]={p[1],p[2],p[3],p[4],#p[5]} end
    return codec.encode(shape)
end
function M.update_materials(slot,frame)
    slot.materials=slot.materials or {}
    for partIndex,part in ipairs(frame[2]) do
        local c=slot.parts[partIndex]
        local cached=slot.materials[partIndex] or {}; slot.materials[partIndex]=cached
        for i,mat in ipairs(part[5]) do
            local key=codec.encode(mat)
            local previous=cached[i]
            if not previous or previous.key~=key then
                -- WindDirection/RippleHeight change while skating. They are
                -- material state, not a new outfit: keep the actor and buffer.
                local layout={mat[1],{}, {}, {}}
                for kind=2,4 do
                    for j,p in ipairs(mat[kind]) do
                        layout[kind][j]=kind==4 and {p[1],p[2]=="" and 0 or 1} or p[1]
                    end
                end
                local layoutKey=codec.encode(layout)
                local mid=previous and previous.mid
                if not previous or previous.layout~=layoutKey or not valid(mid) then
                    mid=c:CreateDynamicMaterialInstance(i-1,asset(mat[1],"MaterialInterface"),FName("None"))
                    assert(valid(mid),"cannot create remote material")
                end
                for _,p in ipairs(mat[2]) do mid:SetScalarParameterValue(FName(p[1]),p[2]) end
                for _,p in ipairs(mat[3]) do
                    mid:SetVectorParameterValue(FName(p[1]),{R=p[2][1],G=p[2][2],B=p[2][3],A=p[2][4]})
                end
                for _,p in ipairs(mat[4]) do
                    if p[2]~="" then mid:SetTextureParameterValue(FName(p[1]),asset(p[2],"Texture")) end
                end
                cached[i]={key=key,layout=layoutKey,mid=mid}
            end
        end
    end
end
function M.validate(frame)
    local function array(a,max) assert(type(a)=="table" and #a<=max,"avatar array limit") end
    local function str(s) assert(type(s)=="string" and #s<=512,"avatar string limit") end
    local function number(n,limit) assert(type(n)=="number" and n==n and math.abs(n)<=limit,"avatar number limit") end
    local function pose(t)
        array(t,10); assert(#t==10)
        for i=1,3 do number(t[i],1e8) end
        local norm=0; for i=4,7 do number(t[i],1.001); norm=norm+t[i]*t[i] end
        assert(norm>.98 and norm<1.02,"invalid pose quaternion")
        for i=4,7 do t[i]=t[i]/math.sqrt(norm) end
        for i=8,10 do number(t[i],100) end
    end
    array(frame,3); assert(frame[1]==1)
    array(frame[2],24); array(frame[3],24); assert(#frame[2]>0 and #frame[2]==#frame[3])
    for i,p in ipairs(frame[2]) do
        array(p,5); str(p[1]); str(p[3]); assert(p[2]=="skeletal" or p[2]=="static")
        array(p[4],256); array(p[5],32)
        array(frame[3][i],2); pose(frame[3][i][1]); array(frame[3][i][2],256)
        assert(#p[4]==#frame[3][i][2]); if p[2]=="static" then assert(#p[4]==0) end
        for j,b in ipairs(p[4]) do str(b); pose(frame[3][i][2][j]) end
        for _,m in ipairs(p[5]) do
            array(m,4); str(m[1])
            for kind=2,4 do
                array(m[kind],128)
                for _,v in ipairs(m[kind]) do
                    array(v,2); str(v[1])
                    if kind==2 then number(v[2],1e6)
                    elseif kind==3 then array(v[2],4); assert(#v[2]==4); for _,n in ipairs(v[2]) do number(n,1e6) end
                    else str(v[2]) end
                end
            end
        end
    end
end
function M.spawn(frame)
    M.validate(frame)
    local world = require("UEHelpers").GetWorld()
    local actor = world:SpawnActor(StaticFindObject("/Script/Engine.Actor"),{X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0})
    assert(valid(actor),"cannot create remote avatar actor")
    local slot = {actor=actor,parts={},appearance=frame[2]}
    local ok,err = pcall(function()
        actor:SetActorEnableCollision(false)
        actor:SetActorTickEnabled(false)
        actor:AddComponentByClass(StaticFindObject("/Script/Engine.SceneComponent"),false,M.engine_transform(identity),false)
        for _,part in ipairs(frame[2]) do
            local skeletal = part[2]=="skeletal"
            local cls = skeletal and "PoseableMeshComponent" or "StaticMeshComponent"
            local c = actor:AddComponentByClass(StaticFindObject("/Script/Engine."..cls),false,M.engine_transform(identity),false)
            assert(valid(c),"cannot create "..cls)
            slot.parts[#slot.parts+1] = c
            c:SetCollisionEnabled(0)
            c:SetVisibility(true,false)
            c:SetHiddenInGame(false,false)
            if skeletal then c:SetSkinnedAssetAndUpdate(asset(part[3],"SkeletalMesh"),true)
            else c:SetStaticMesh(asset(part[3],"StaticMesh")) end
        end
        M.update_materials(slot,frame)
        M.apply(slot,frame)
    end)
    if not ok then actor:K2_DestroyActor(); error(err) end
    return slot
end
function M.apply(slot,frame)
    if not slot.rigKeys then
        slot.rigKeys,slot.boneNames,slot.leaders={},{},{}
        for i,p in ipairs(slot.appearance) do
            slot.rigKeys[i]=codec.encode(p[4])
            slot.boneNames[i]={}
            for j,name in ipairs(p[4]) do slot.boneNames[i][j]=FName(name) end
        end
    end
    local leaders={}
    local function same_pose(a,b)
        if #a==0 or #a~=#b then return false end
        for j,t in ipairs(a) do
            for k=1,10 do if t[k]~=b[j][k] then return false end end
        end
        return true
    end
    slot.sharedParts=0
    for i,c in ipairs(slot.parts) do
        local pose = frame[3][i]
        c:K2_SetWorldTransform(M.engine_transform(pose[1]),false,{},true)
        local leader=0
        if #pose[2]>0 then
            for j=1,i-1 do
                if leaders[j]==0 and slot.rigKeys[j]==slot.rigKeys[i]
                    and same_pose(pose[2],frame[3][j][2]) then leader=j;break end
            end
            if (slot.leaders[i] or 0)~=leader then
                c:SetLeaderPoseComponent(leader>0 and slot.parts[leader] or nil,true,false)
                slot.leaders[i]=leader
            end
        end
        leaders[i]=leader
        if leader>0 then
            slot.sharedParts=slot.sharedParts+1
        else
            for j,bone in ipairs(slot.boneNames[i]) do
                c:SetBoneTransformByName(bone,M.engine_transform(pose[2][j]),1)
            end
        end
    end
end
function M.census(pawn,dir)
    local frame = M.capture(pawn)
    local rows={"parts="..#frame[2]}
    for i,p in ipairs(frame[2]) do
        rows[#rows+1]=p[1].." "..p[2].." "..p[3].." bones="..#p[4]
        for _,mat in ipairs(p[5]) do
            rows[#rows+1]=mat[1].." scalar="..#mat[2].." vector="..#mat[3].." texture="..#mat[4]
        end
    end
    local f=assert(io.open(dir.."/avatar-census.txt","wb")); f:write(table.concat(rows,"\n")); f:close()
    return frame
end
return M
