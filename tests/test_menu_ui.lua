-- Menu lifecycle and native polling contract, independent of UE4SS rendering.
package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local objects,keys={},{}
local methods={}
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
local function object(kind)
    local o=setmetatable({kind=kind,Font={}}, {__index=function(self,key)
        if methods[key] then return methods[key] end
        if key:match('^AddChild') then return function() return object('slot') end end
        if key:match('^Set') or key=='ClearChildren' or key=='AddToViewport' or key=='ScrollWidgetIntoView' then return function() end end
    end})
    objects[#objects+1]=o
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
    set=function(key,value) writes=writes+1;data[key]=value end,
    reset=function() end,save=function() return true end})
keys.F5();assert(menu.is_open() and pc.move==1 and pc.look==1 and pc.bShowMouseCursor)
tick();assert(writes==0,'Opening must never clamp or write game values')
local slider
for _,o in ipairs(objects) do if o.kind=='/Script/UMG.Slider' and o.value~=nil then slider=o;break end end
assert(slider);slider:SetValue(1.5);tick();assert(data.speedMultiplier==1.5 and writes==1)
tick();assert(writes==1,'Unchanged values must not repeatedly apply settings')
local toggle
for _,o in ipairs(objects) do if o.kind=='/Script/UMG.Button' and o.content and o.content.text=='OFF' then toggle=o end end
assert(toggle);toggle.hovered=true;keys.LEFT_MOUSE_BUTTON();tick()
assert(data.triggerSteering==true and writes==2,'False must remain a working editable toggle')
toggle.pressed=true;tick();assert(writes==2,'Mouse latch and native pressed edge must not double-activate')
keys.F5();assert(not menu.is_open() and pc.move==0 and pc.look==0 and not pc.bShowMouseCursor)
keys.F5();assert(menu.is_open());world.address=2;tick()
assert(not menu.is_open() and pc.move==0 and pc.look==0,'Travel must release input')
print('menu no-write open, live settings, click deduplication, close and travel cleanup passed')

