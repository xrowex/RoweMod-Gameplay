package.path='ue4ss/Mods/RoweModGameplay/Scripts/?.lua;'..package.path
local serial,now=0,10
os.time=function() return now end
local function object(fields)
    serial=serial+1
    local o=fields or {};o.id=serial
    function o:IsValid() return not self.dead end
    function o:GetAddress() return self.id end
    return o
end
local world=object()
local parent=object({children={}})
function parent:IsA() return true end
function parent:AddChildToVerticalBox(child)
    self.children[#self.children+1]=child;child.parent=self
    return {SetPadding=function() end,SetHorizontalAlignment=function() end}
end
local function pause_widget()
    local p=object({active=true,Controls={GetParent=function() return parent end},world=world})
    function p:IsVisible() return self.active end
    function p:IsActivated() return self.active end
    function p:GetWorld() return self.world end
    return p
end
local pause=pause_widget()
local candidates={pause}
local hook,registrations,opens= nil,0,0
local cls,fn,lib=object(),object(),object()
function lib:Create()
    local e=object({Button=object(),ButtonText=object({SetText=function(self,text) self.text=text end})})
    function e:GetParent() return self.parent end
    function e:RemoveFromParent() self.parent=nil end
    return e
end
function StaticFindObject(path)
    if path:find('WidgetBlueprintLibrary',1,true) then return lib end
    if path:find(':BndEvt',1,true) then return fn end
    return cls
end
function FindAllOf(name) assert(name=='W-pause-main_C');return candidates end
function RegisterHook(_,callback) registrations=registrations+1;hook=callback;return 1,2 end
function FText(text) return text end
local tick
package.loaded.game_thread={loop=function(_,callback) tick=callback end}
package.loaded.UEHelpers={GetWorld=function() return world end,GetPlayerController=function() return object() end}
local opened=false
local integration=require('pause_menu')
integration.init({is_open=function() return opened end,open_from_pause=function(p,b)
    assert(p==pause and b==parent.children[#parent.children].Button);opens=opens+1
end})
tick();assert(#parent.children==1 and registrations==1 and parent.children[1].ButtonText.text=='ROWEMOD')
for _=1,20 do now=now+1;tick() end
assert(#parent.children==1,'No duplicate pause entries')
hook({get=function() return object() end});tick();assert(opens==0,'Original game buttons are unaffected')
hook({get=function() return parent.children[1] end});assert(opens==0,'Defer work out of Blueprint callback')
tick();assert(opens==1)
hook({get=function() return parent.children[1] end});pause.active=false;tick();assert(opens==1)
pause.active=true;opened=true
hook({get=function() return parent.children[1] end});tick();assert(opens==1);opened=false
-- A queued click and old UI references must never cross worlds.
hook({get=function() return parent.children[1] end});world=object();tick();assert(opens==1)
pause=pause_widget();candidates={pause};now=now+2;tick()
assert(#parent.children==2 and registrations==1,'New world reattaches with one persistent hook')
local original=pause
original.active=false;pause=pause_widget();candidates={original,pause};now=now+2;tick()
assert(#parent.children==3)
pause.active=false;original.active=true;now=now+2;tick()
assert(#parent.children==3,'Reactivated cached pause menu reuses its entry')
print('Pause entry ownership, deferred click, duplicate prevention and world cleanup passed')
