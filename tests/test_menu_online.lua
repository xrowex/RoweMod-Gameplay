package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local now=1000
os.time=function() return now end
package.loaded["mp.mailbox"]={default_dir=function() return "test" end}
local opened,connected,disconnected,retried=0,0,0,0
package.loaded["mp.online"]={open=function() opened=opened+1;return true end}
local stateText,files=nil,{}
io.open=function(path,mode)
    if mode=="rb" then if not stateText then return nil end;return {read=function() return stateText end,close=function() end} end
    local content=""
    return {write=function(_,s) content=content..s end,close=function() files[path]=content end}
end
os.rename=function(a,b) files[b]=files[a];files[a]=nil;return true end
local function state(role,lobby)
    stateText="updated\t"..now.."\nphase\tready\nmessage\tChoose a session\nrole\t"..(role or "idle").."\nlobby\t"..(lobby or "0").."\nplayers\t1\n"
end
local page=require("menu_online")
local travel={phase="idle"}
local rosterHealth={lobby="123",players={{id="guest",status="Avatar failed",map="OutdoorSkatepark"}}}
page.init({connect=function() connected=connected+1 end,disconnect=function() disconnected=disconnected+1 end,
    players=function() return rosterHealth end,map_status=function() return travel end,retry_map=function() retried=retried+1 end})
local widgets,buttons,entries,messages={},{},{},{}
local rebuilds=0
local function widget(text)
    local w={text=text,alive=true}
    function w:GetText() assert(self.alive,'Detached field read');return {ToString=function() return self.text end} end
    function w:SetVisibility(value) assert(self.alive);self.visibility=value end
    widgets[#widgets+1]=w;return w
end
local ui={construct=function() return widget() end,label=function(_,text) return widget(text) end,
    card=function(_,title,subtitle) return widget(title) end,vadd=function() end,hadd=function() end,
    settext=function(w,text) assert(w.alive,'Detached status written');w.text=text end,
    entry=function(_,text) local w=widget(text);entries[#entries+1]=w;return w end,
    button=function(_,text,fn) buttons[text]=fn;return widget(text) end,
    action=function(_,text,fn) buttons[text]=fn end,
    message=function(text) messages[#messages+1]=text end,rebuild=function() rebuilds=rebuilds+1 end}
local function mount()
    page.unmount(true)
    for _,w in ipairs(widgets) do w.alive=false end
    widgets={};buttons={};entries={};page.build(ui,{})
end
mount();assert(opened==1 and #entries==0)
assert(buttons.JOIN and buttons.HOST and not buttons['START STEAM CONNECTION'])
assert(not buttons['HOST SESSION'] and not buttons['JOIN CODE'],'Progressive disclosure keeps the initial view clean')
buttons.HOST();mount();assert(#entries==1 and buttons['HOST SESSION'])
entries[1].text="My session";buttons['HOST SESSION']();assert(opened==1,'Deduplicate startup while preserving intended host action')
page.unmount(true);for _,w in ipairs(widgets) do w.alive=false end
now=1001;state();page.update() -- closed menu still finishes startup and request
assert(connected>=1)
local hosted=false
for _,text in pairs(files) do if text:find('action\thost') and text:find('name\tMy session') then hosted=true end end
assert(hosted,'Complete the requested action after Steam becomes ready without reopening the menu')
now=1002;state('host','123');page.update();mount()
assert(buttons['LEAVE SESSION'] and not buttons.HOST and #entries==0)
stateText=stateText..'player\tself\tMe\t1\t1\tOutdoorSkatepark\t1\nplayer\tguest\tFriend\t0\t0\tOutdoorSkatepark\t1\n'
now=now+1;page.update();mount()
local listText={};for _,w in ipairs(widgets) do listText[#listText+1]=w.text or '' end
local rosterText=table.concat(listText,'\n')
assert(rosterText:find('HOST / YOU',1,true) and rosterText:find('Friend',1,true) and rosterText:find('Avatar failed',1,true))
local before,count=rebuilds,#widgets
rosterHealth.players[1].status='Avatar active'
rosterHealth.players[1].map='Observatory'
page.tick('Multiplayer')
assert(rebuilds==before and #widgets==count,'Health and park changes must not rebuild controls')
seen=false;for _,w in ipairs(widgets) do if w.text=='Avatar active   |   Observatory' then seen=true end end;assert(seen)
stateText=stateText..'player\tguest2\tNew friend\t0\t0\tTheBigHall\t1\n'
now=now+1;page.tick('Multiplayer')
assert(rebuilds==before and #widgets==count,'Joining players update reserved rows in place')
state('host','123');now=now+1;page.tick('Multiplayer')
assert(rebuilds==before,'Departing players must not rebuild controls')
buttons['COPY DIAGNOSTICS']();now=now+1;state('host','123');page.update()
local copied=false;for _,text in pairs(files) do if text:find('action	diagnostics',1,true) then copied=true end end
assert(copied,'Copy diagnostics reaches the companion')

buttons['LEAVE SESSION']();page.update();assert(disconnected==1)
now=1003;state();page.update();mount();assert(entries[1].text=='My session')
buttons.JOIN();mount();assert(#entries==0 and buttons['JOIN WITH A CODE'])
buttons['JOIN WITH A CODE']();mount();assert(#entries==1 and buttons['JOIN CODE'])
entries[1].text='109775244182498723';mount();assert(entries[1].text=='109775244182498723')
now=1004;state('join','123');page.update();travel={phase='loading',message='Loading Observatory...'};mount();page.tick('Multiplayer')
local seen=false;for _,w in ipairs(widgets) do if w.text=='Loading Observatory...' then seen=true end end;assert(seen)
travel={phase='failed',message='Retry loading'};mount();buttons['RETRY MAP LOAD']();assert(retried==1)
-- Never read native fields after world teardown.
for _,w in ipairs(widgets) do w.alive=false end;page.unmount(false)
now=1010;stateText=nil;page.update();mount();buttons['RETRY CONNECTION']();assert(opened==2)
now=1041;page.update();mount();assert(buttons['RETRY CONNECTION'])
page.tick('Multiplayer');seen=false;for _,w in ipairs(widgets) do if w.text and w.text:find('Steam did not respond') then seen=true end end;assert(seen)
print('Clean Join/Host views, hidden code entry, automatic startup, deferred actions, travel status and widget lifetime passed')
