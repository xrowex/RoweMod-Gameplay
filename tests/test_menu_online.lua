package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local now=1000
os.time=function() return now end
local root=arg[1].."/Steam"
-- The test runner supplies existing folders; avoid shell calls from Lua.
package.loaded["mp.mailbox"]={default_dir=function() return arg[1] end}
local opened,connected=0,0
package.loaded["mp.online"]={open=function() opened=opened+1;return true end}
local page=require("menu_online")
page.init({connect=function() connected=connected+1 end,disconnect=function() end})
local widgets,buttons,entries,messages={},{},{},{}
local rebuilt=0
local function widget(text)
    local w={text=text,alive=true}
    function w:IsValid() assert(self.alive,'Stale native handle inspected');return true end
    function w:GetText() assert(self.alive,'Detached field read');return {ToString=function() return self.text end} end
    widgets[#widgets+1]=w;return w
end
local ui={construct=function() return widget() end,label=function(_,text) return widget(text) end,
    vadd=function() end,hadd=function() end,
    settext=function(w,text) assert(w.alive,'Detached status label written');w.text=text end,
    entry=function(_,text) local w=widget(text);entries[#entries+1]=w;return w end,
    button=function(_,text,action) buttons[text]=action;return widget(text) end,
    message=function(text) messages[#messages+1]=text end,
    rebuild=function() rebuilt=rebuilt+1 end}
local function state(text)
    local f=assert(io.open(root.."/menu_state.txt","wb"));f:write(text);f:close()
end
page.build(ui,{})
entries[1].text="My session";entries[2].text="109775244182498723"
buttons['START STEAM CONNECTION']();assert(opened==1 and connected==0)
buttons['START STEAM CONNECTION']();assert(opened==1,'Do not spawn duplicate helpers while starting')
now=1031;page.tick('Multiplayer');assert(messages[#messages]:find('did not become ready'))
now=1032;page.tick('Multiplayer');assert(messages[#messages]:find('did not become ready'))
page.unmount(true)
for _,w in ipairs(widgets) do w.alive=false end
page.tick('Movement')
page.build(ui,{})
assert(entries[3].text=='My session' and entries[4].text=='109775244182498723','Preserve drafts before removing widgets')
buttons['START STEAM CONNECTION']();assert(opened==2)
state('updated\t1033\nphase\terror\nmessage\tSteam startup failed: Steam is offline\n')
now=1033;page.tick('Multiplayer');assert(messages[#messages]:find('Steam is offline'))
now=1040;page.tick('Multiplayer');assert(messages[#messages]:find('Steam is offline'),'Keep startup errors visible beyond heartbeat expiry')
buttons['START STEAM CONNECTION']();assert(opened==3)
state('updated\t1041\nphase\tready\nmessage\tChoose Host or Friends\nrole\tidle\nplayers\t0\n')
now=1041;page.tick('Multiplayer');assert(connected==1 and messages[#messages]:find('Steam ready'))
assert(not messages[#messages]:find('starting'),'Replace the starting footer on readiness')
assert(rebuilt==0,'Heartbeat changes must not rebuild native widgets')
-- Travel can destroy native objects before the menu notices. Never read drafts then.
for _,w in ipairs(widgets) do w.alive=false end
page.unmount(false);page.build(ui,{})
print('Multiplayer stale-widget lifecycle, draft preservation, launch timeout, errors and readiness passed')
