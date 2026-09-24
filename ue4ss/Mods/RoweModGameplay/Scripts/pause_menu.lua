-- Reuse Rollout's installed pause-menu button. No cooked game assets shipped.
-- Paths/properties verified against the installed UE 5.4 widget exports.
local M={}
local helpers=require("UEHelpers")
local dispatch=require("game_thread")
local buttonClass="/Game/MainFolder/UI/modular/buttons/W-small-button.W-small-button_C"
local clickPath=buttonClass..":BndEvt__W-big-button_Button_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature"
local menu,worldId,pause,entry,hookIds,hookAddress,pending
local retryAt=0
local bindings={}
local function valid(o) return o and o:IsValid() end
local function visible(o) return valid(o) and o:IsVisible() and o:IsActivated() end
local function clicked(context)
    -- A single persistent hook filters out every original game button. Queue
    -- data, not a fresh Lua/engine callback, until the native timer runs.
    if valid(entry) and context:get():GetAddress()==entry:GetAddress() then pending=worldId end
end
local function attach(candidate,world)
    local parent=candidate.Controls:GetParent()
    assert(valid(parent) and parent:IsA(StaticFindObject("/Script/UMG.VerticalBox")),"Pause layout changed")
    local cls=StaticFindObject(buttonClass)
    local fn=StaticFindObject(clickPath)
    assert(valid(cls) and valid(fn),"Stock button class or click handler unavailable")
    if hookAddress~=fn:GetAddress() then
        -- Hooks on unloaded Blueprint functions do not survive a class reload.
        if hookIds then pcall(UnregisterHook,clickPath,hookIds[1],hookIds[2]) end
        hookIds={RegisterHook(clickPath,clicked)};hookAddress=fn:GetAddress()
    end
    local lib=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local created=lib:Create(world,cls,helpers.GetPlayerController())
    if not valid(created) then return end
    local ok,err=pcall(function()
        created.Text=FText("ROWEMOD")
        local slot=parent:AddChildToVerticalBox(created)
        slot:SetPadding({Left=5,Top=5,Right=5,Bottom=5})
        slot:SetHorizontalAlignment(0)
        -- PreConstruct runs when added; set the live text afterward as well.
        assert(valid(created.ButtonText) and valid(created.Button),"Stock button fields unavailable")
        created.ButtonText:SetText(FText("ROWEMOD"))
    end)
    if not ok then created:RemoveFromParent();error(err) end
    pause=candidate;entry=created
    bindings[candidate:GetAddress()]={pause=candidate,entry=created}
    print("[RoweMenu] pause-menu entry attached")
end
function M.tick()
    local world=helpers.GetWorld()
    if not valid(world) then pause=nil;entry=nil;pending=nil;worldId=nil;bindings={};return end
    local address=world:GetAddress()
    if worldId~=address then
        -- Never inspect widget trees belonging to a world being torn down.
        worldId=address;pause=nil;entry=nil;pending=nil;retryAt=0;bindings={}
    end
    if pending then
        local requested=pending;pending=nil
        if requested==worldId and visible(pause) and valid(entry) and not menu.is_open() then
            menu.open_from_pause(pause,entry.Button)
        end
    end
    if menu.is_open() then return end
    if visible(pause) and valid(entry) and valid(entry:GetParent()) then return end
    if os.time()<retryAt then return end
    retryAt=os.time()+1
    for _,candidate in ipairs(FindAllOf("W-pause-main_C") or {}) do
        if visible(candidate) and candidate:GetWorld():GetAddress()==worldId then
            local prior=bindings[candidate:GetAddress()]
            if prior and valid(prior.pause) and valid(prior.entry) and valid(prior.entry:GetParent()) then
                pause=candidate;entry=prior.entry;break
            end
            local ok,err=pcall(attach,candidate,world)
            if not ok then retryAt=os.time()+30;print("[RoweMenu] pause entry unavailable; F5 still works: "..tostring(err)) end
            break
        end
    end
end
function M.init(renderer)
    menu=renderer
    dispatch.loop(250,M.tick)
end
return M
