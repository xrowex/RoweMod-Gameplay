package.path='ue4ss/Mods/RoweModGameplay/Scripts/?.lua;'..package.path
local now=100
os.time=function() return now end
os.clock=function() return 0 end
package.loaded.UEHelpers={GetPlayerController=function() end}
local maps=require('mp.mapinfo')
maps.current=function() return {id='OutdoorSkatepark'} end
package.loaded['mp.capture']={local_pawn=function() end,merge_prop_map=function() return {} end}
package.loaded.game_thread={loop=function() return 1 end}
local inbox={}
local bridgeStatus='host transport=steam lobby=100 peers=3'
local box={dir=arg[1],write_line=function() end,write_status=function() end,
 read_bridge_status=function() return bridgeStatus end,
 poll_inbox=function() local r=inbox;inbox={};return r end}
package.loaded['mp.mailbox']={open=function() return box end}
local seen={}
package.loaded['mp.ghost']={create_manager=function() return {ghosts={},clear=function() end,
 ensure=function() end,remove=function(_,p) seen[p]=nil end,render=function() end,
 apply_frame=function(_,p,msg)
   if msg.frame[2][1][3]=='/Game/Missing.Missing' then error('missing shared asset: /Game/Missing.Missing') end
   seen[p]=msg.frame[3][1][1][1];return true
 end} end}
local session=require('mp.session')
local protocol=require('mp.protocol')
local function frame(x,asset)
 return {1,{{'Body','static',asset or '/Game/Body.Body',{}, {}}},{{{x,0,0,0,0,0,1,1,1,1},{}}}}
end
local function receive(peer,line) inbox[#inbox+1]='@'..peer..'|'..line end
session.start({online=true,isHost=true});session.tick()
for i=1,3 do receive('peer'..i,protocol.encode_hello(1,'same name','OutdoorSkatepark')) end
session.tick()
for tick=1,60 do
 for i=1,3 do receive('peer'..i,protocol.encode_frame(tick,'OutdoorSkatepark',frame(i*100+tick))) end
 session.tick()
 for i=1,3 do assert(seen['peer'..i]==i*100+tick,'All three remote origins must move independently') end
end
-- Loading one player must not suppress the remaining players.
receive('peer2',protocol.encode_map(61,'TheBigHall'))
for i=1,3 do receive('peer'..i,protocol.encode_frame(62,'OutdoorSkatepark',frame(i*100+62))) end
session.tick();assert(seen.peer1==162 and seen.peer3==362 and seen.peer2==nil)
receive('peer2',protocol.encode_map(63,'OutdoorSkatepark'))
receive('peer2',protocol.encode_frame(64,'OutdoorSkatepark',frame(264)))
session.tick();assert(seen.peer2==264)
-- A missing outfit on one sender should remain diagnosable without blocking others.
receive('peer1',protocol.encode_frame(65,'OutdoorSkatepark',frame(165,'/Game/Missing.Missing')))
receive('peer3',protocol.encode_frame(65,'OutdoorSkatepark',frame(365)))
now=102;session.tick();assert(seen.peer3==365)
local f=assert(io.open(arg[1]..'/visibility.txt','rb'));local report=f:read('*a');f:close()
assert(report:find('missing shared asset',1,true))
assert(report:find('peer=peer2',1,true) and report:find('peer=peer3',1,true))
local players=session.players();assert(players.lobby=='100' and #players.players==3)
assert(players.players[1].status=='Avatar failed')
-- A partial status read must not turn a host into a joiner or clear the roster.
now=104;bridgeStatus='';session.tick()
assert(session.players().lobby=='100' and #session.players().players==3)
assert(session.request_map('OutdoorSkatepark'),'Host authority survives an empty status read')
now=105;bridgeStatus='host transport=steam lobby=';session.tick()
assert(session.players().lobby=='100' and #session.players().players==3)
now=106;bridgeStatus='idle transport=steam lobby=0 peers=0';session.tick()
assert(session.players().lobby=='0' and #session.players().players==0,'An explicit leave still clears the roster')
session.stop()
print('Three remote players: sustained independent poses, isolated map gates and asset-error diagnostics passed')
