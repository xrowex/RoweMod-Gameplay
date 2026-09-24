-- Menu lifecycle and native polling contract, independent of UE4SS rendering.
package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local objects,keys={},{}
local methods={}
local unmounted=false
local focused,scroll
local now=0
os.clock=function() return now end
function methods:ClearChildren() assert(unmounted,'Release page references before detaching widgets');unmounted=false end
function methods:IsValid() return true end
function methods:GetAddress() return self.address or 1 end
function methods:SetText(value) self.text=value end
function methods:GetText() return {ToString=function() return self.text end} end
function methods:SetContent(value) self.content=value end
function methods:GetContent() return self.content end
function methods:SetValue(value) self.value=value end
function methods:GetValue() return self.value end
function methods:IsPressed() return self.pressed or false end
function methods:IsHovered() return self.hovered or false end
function methods:IsInputKeyDown() return false end
function methods:SetIgnoreMoveInput(on) self.move=(self.move or 0)+(on and 1 or -1) end
function methods:SetIgnoreLookInput(on) self.look=(self.look or 0)+(on and 1 or -1) end
function methods:RemoveFromParent() self.removed=true end
function methods:SetVisibility(value) self.visibility=value end
function methods:SetKeyboardFocus() focused=self end
function methods:GetScrollOffset() return self.offset or 0 end
function methods:SetScrollOffset(value) self.offset=value end
function methods:SetIsEnabled(value) self.enabled=value end
function methods:IsActivated() return self.active~=false end
function methods:IsVisible() return self.active~=false end
function methods:SetInputMode_UIOnlyEx(_,focus) self.uiFocus=focus end
local function object(kind)
    local o=setmetatable({kind=kind,Font={}}, {__index=function(self,key)
        if methods[key] then return methods[key] end
        if key:match('^AddChild') then return function() return object('slot') end end
        if key:match('^Set') or key=='ClearChildren' or key=='AddToViewport' or key=='ScrollWidgetIntoView' then return function() end end
    end})
    objects[#objects+1]=o
    if kind=='/Script/UMG.ScrollBox' then scroll=o end
    return o
end
function StaticFindObject(path) return object(path) end
function StaticConstructObject(cls) return object(cls.kind) end
function FName(value) return value end
function FText(value) return value end
Key=setmetatable({}, {__index=function(_,key) return key end})
function RegisterKeyBind(key,fn) keys[key]=fn end
local pc,world=object('pc'),object('world')
pc.bShowMouseCursor=false
package.loaded.UEHelpers={GetPlayerController=function() return pc end,GetWorld=function() return world end,GetGameInstance=function() return object('gi') end}
local tick
package.loaded.game_thread={wrap=function(fn) return fn end,loop=function(_,fn) tick=fn end}
local data={speedMultiplier=1.25,triggerSteering=false}
local writes=0
local menu=require('rowe_menu')
menu.init({get=function(key) return data[key] end,
    unmount=function() unmounted=true end,
    set=function(key,value) writes=writes+1;data[key]=value end,
    reset=function() end,save=function() return true end})
keys.F5();assert(menu.is_open() and pc.move==1 and pc.look==1 and pc.bShowMouseCursor)
tick();assert(writes==0,'Opening must never clamp or write game values')
local slider
for _,o in ipairs(objects) do if o.kind=='/Script/UMG.Slider' and o.value~=nil then slider=o;break end end
assert(slider);slider:SetValue(1.531525);tick();assert(data.speedMultiplier==1.55 and writes==1)
tick();assert(writes==1,'Unchanged values must not repeatedly apply settings')
slider:SetValue(1.551);tick();assert(writes==1,'Mouse jitter inside the same step must not write again')
assert(slider:GetValue()==1.55)
local toggle
for _,o in ipairs(objects) do if o.kind=='/Script/UMG.Button' and o.content and o.content.text=='OFF' then toggle=o end end
assert(toggle);toggle.hovered=true;keys.LEFT_MOUSE_BUTTON();tick()
assert(data.triggerSteering==true and writes==2,'False must remain a working editable toggle')
toggle.pressed=true;tick();assert(writes==2,'Mouse latch and native pressed edge must not double-activate')
keys.F5();assert(not menu.is_open() and pc.move==0 and pc.look==0 and not pc.bShowMouseCursor)
keys.F5();assert(menu.is_open());world.address=2;tick()
assert(not menu.is_open() and pc.move==0 and pc.look==0,'Travel must release input')
-- Keep a selected session by identity when a refresh inserts/removes rows.
local sessions={'one','two'}
local joined
menu.init({unmount=function() unmounted=true end,get=function() end,
    multiplayer=function(ui,parent)
        for _,id in ipairs(sessions) do ui.action(parent,'JOIN SESSION',function() joined=id end,true,'join:'..id) end
    end})
menu.open()
for _,o in ipairs(objects) do o.hovered=false end
local tab
for _,o in ipairs(objects) do if o.content and o.content.text=='MULTIPLAYER' then tab=o end end
now=now+1;tab.hovered=true;keys.LEFT_MOUSE_BUTTON();tick();tick();tab.hovered=false
for _=1,6 do keys.DOWN() end;scroll.offset=140 -- close, four tabs, two sessions
assert(focused.content.text=='JOIN SESSION')
sessions={'new','one','two'};menu.rebuild();tick()
assert(scroll.offset==140,'Refresh preserves scroll position')
now=now+1;keys.RETURN();assert(joined=='two','Refresh must retain the same session, not an index')
joined=nil;sessions={'new','one'};menu.rebuild();tick()
now=now+1;keys.RETURN();assert(joined==nil,'Removed session must not select another join action')
menu.close()
-- Closing an overlay opened from pause restores the pause button and input locks.
local pause,entry=object('pause'),object('entry')
menu.open_from_pause(pause,entry);assert(menu.is_open() and pause.enabled==false)
menu.close();assert(pause.enabled and focused==entry and pc.move==0 and pc.look==0)
menu.open_from_pause(pause,entry);pause.active=false;tick()
assert(not menu.is_open() and pause.enabled and not pc.bShowMouseCursor,'Closing the stock pause menu must release the overlay')
print('menu no-write open, live settings, click deduplication, close and travel cleanup passed')

