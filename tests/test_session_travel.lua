package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local now,map,pawnReady=100,"OutdoorSkatepark",true
os.time=function() return now end
os.clock=function() return 0 end
package.loaded.UEHelpers={GetPlayer=function() return nil end,GetPlayerController=function() return nil end}
local maps=require('mp.mapinfo')
maps.current=function() return {id=map} end
local loads=0
maps.travel=function() loads=loads+1;return true,'requested' end
local pawn={IsValid=function() return true end,GetFullName=function() return 'local player' end,
    K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end,GetActorScale3D=function() return {X=1,Y=1,Z=1} end}
package.loaded['mp.capture']={local_pawn=function() return pawnReady and pawn or nil end,merge_prop_map=function() return {} end}
local inbox,outbox={},{}
local role,lobby='join','100'
local box={dir=arg[1],write_line=function(_,line) outbox[#outbox+1]=line end,write_status=function() end,
    read_bridge_status=function() return role..' transport=steam lobby='..lobby..' peers=1' end,
    poll_inbox=function() local lines=inbox;inbox={};return lines end}
package.loaded['mp.mailbox']={open=function() return box end}
package.loaded['mp.ghost']={create_manager=function() return {ghosts={},clear=function() end,ensure=function() end,remove=function() end,render=function() end} end}
package.loaded.game_thread={loop=function() return 1 end}
local session=require('mp.session')
local protocol=require('mp.protocol')
session.start({online=true,autoTravelToHostMap=true,isHost=false,role='join'})
session.tick()
inbox={protocol.encode_hello(1,'Host','TheBigHall'),protocol.encode_map_req(2,'TheBigHall')}
session.tick();assert(loads==1 and not session.maps_ok())
for _,line in ipairs(outbox) do assert(not line:match('^MACK|.*|TheBigHall|1$'),'Cannot ACK a map before arrival') end
inbox={protocol.encode_map_req(3,'TheBigHall')};session.tick();assert(loads==1)
map='unknown';pawnReady=false;session.tick();assert(not session.maps_ok())
map='TheBigHall';session.tick();assert(not session.maps_ok(),'Player spawn is part of travel completion')
pawnReady=true;session.tick();assert(session.maps_ok() and session.map_status().phase=='ready')
local arrived=false;for _,line in ipairs(outbox) do if line:match('^MACK|.*|TheBigHall|1$') then arrived=true end end;assert(arrived)
now=101;role='host';session.tick();inbox={protocol.encode_map_req(4,'Observatory')};session.tick();assert(loads==1,'Guests cannot move the host')
outbox={};map='unknown';session.tick();map='OutdoorSkatepark';session.tick()
local announced=false;for _,line in ipairs(outbox) do if line:match('^MREQ|.*|OutdoorSkatepark$') then announced=true end end
assert(announced,'Announce host arrival even when the map was temporarily unknown during travel')
now=102;role='join';lobby='200';session.tick();inbox={protocol.encode_map_req(5,'Observatory')};session.tick();assert(loads==2)
now=103;role='idle';lobby='0';session.tick();inbox={protocol.encode_map_req(6,'TheBigHall')};session.tick();assert(loads==2,'Old inbox requests must not move an idle/disconnected player')
session.stop();assert(not session.is_active())
print('Actual session map gating, arrival ACK, host authority and reconnect state passed')
