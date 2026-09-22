package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local now=100
os.time=function() return now end
local world={IsValid=function() return true end,GetName=function() return "OutdoorSkatepark" end}
package.loaded.UEHelpers={GetWorld=function() return world end}
local loaded,closed={},0
function FName(value) return value end
function StaticFindObject() return {IsValid=function() return true end,
    OpenLevel=function(_,_,path) assert(closed>0);loaded[#loaded+1]=path end} end
package.loaded.rowe_menu={is_open=function() return true end,close=function() closed=closed+1 end}
local map=require('mp.mapinfo')
assert(map.current().id=='OutdoorSkatepark','Missing first name candidate must not hide valid later candidates')
assert(map.travel('Observatory'))
assert(loaded[1]=='/Game/MainFolder/Maps/Observatory/Observatory')
assert(not map.travel('Observatory?listen') and not map.travel('MissingMap'))
local acks,calls={},0
local travel=require('mp.travel').new(function(target) calls=calls+1;return true end,
    function(actual,ok) acks[#acks+1]={actual,ok} end)
travel:request('TheBigHall','OutdoorSkatepark',true)
assert(calls==1 and #acks==0 and travel.phase=='loading','A request is not arrival')
for _=1,20 do travel:request('TheBigHall','OutdoorSkatepark',true) end
assert(calls==1,'Host heartbeats must not restart map loading')
travel:update('TheBigHall',false);assert(#acks==0,'Wait for the local player to spawn')
travel:update('TheBigHall',true);assert(acks[1][1]=='TheBigHall' and acks[1][2] and travel.phase=='ready')
travel:request('Observatory','TheBigHall',true);travel:request('OutdoorSkatepark','TheBigHall',false)
assert(calls==2,'Do not issue another OpenLevel while one is pending')
travel:update('Observatory',true);assert(calls==3 and travel.target=='OutdoorSkatepark')
now=161;travel:update('Observatory',true);assert(travel.phase=='failed' and not acks[#acks][2])
travel:request('OutdoorSkatepark','Observatory',true);assert(calls==3,'Failed requests must not loop')
travel:request('OutdoorSkatepark','Observatory',true,true);assert(calls==4)
travel:update('OutdoorSkatepark',true)
travel:request('StartMenu','OutdoorSkatepark',true);assert(travel.phase=='waiting' and calls==4)
travel:request('OutdoorSkatepark','OutdoorSkatepark',true);assert(travel.phase=='ready' and calls==4)
print('Verified map paths, no console interpolation, deduplicated loading, arrival ACKs, timeout/retry and host changes passed')
