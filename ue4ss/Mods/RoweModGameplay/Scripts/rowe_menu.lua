-- Native UMG shell. Construction technique informed by MIT ue4ss-ModMenu;
-- see docs/licenses/ModMenu.txt. Input uses our persistent dispatcher.
local M = {}
local helpers = require("UEHelpers")
local dispatch = require("game_thread")
local schema = require("menu_schema")
local limits = require("menu_values")
local S = {open=false, page="Movement", serial=0, controls={}, selected=1}
local C = {
    panel={R=.025,G=.025,B=.03,A=.98}, row={R=.09,G=.09,B=.105,A=1},
    white={R=.94,G=.94,B=.94,A=1}, muted={R=.6,G=.6,B=.65,A=1},
    yellow={R=1,G=.88,B=0,A=1}, purple={R=.3,G=0,B=1,A=1},
}
local function valid(obj) return obj and obj:IsValid() end
local function construct(kind, outer)
    S.serial=S.serial+1
    local cls=assert(StaticFindObject("/Script/UMG."..kind),kind)
    local obj=StaticConstructObject(cls,outer,FName("RoweMenu_"..kind.."_"..S.serial))
    assert(valid(obj),"Unable to construct "..kind)
    return obj
end
local function settext(widget, text) widget:SetText(FText(tostring(text))) end
local function label(parent,text,size,color)
    local w=construct("TextBlock",parent)
    w.Font.Size=size or 20
    if valid(S.font) then w.Font.FontObject=S.font end
    w:SetColorAndOpacity({SpecifiedColor=color or C.white,ColorUseRule=0})
    settext(w,text)
    return w
end
local function padding(slot,p)
    slot:SetPadding({Left=p,Top=p,Right=p,Bottom=p})
end
local function vadd(parent,child,p)
    local slot=parent:AddChildToVerticalBox(child)
    padding(slot,p or 4)
    slot:SetHorizontalAlignment(0)
    return slot
end
local function hadd(parent,child,fill)
    local slot=parent:AddChildToHorizontalBox(child)
    padding(slot,4)
    slot:SetVerticalAlignment(2)
    if fill then slot:SetSize({SizeRule=1,Value=1}) end
    return slot
end
local function box(parent,height,width)
    local w=construct("SizeBox",parent)
    if height then w:SetHeightOverride(height) end
    if width then w:SetWidthOverride(width) end
    return w
end
local function button(parent,text,action,accent)
    local b=construct("Button",parent)
    b:SetBackgroundColor(accent and C.purple or C.row)
    b:SetContent(label(b,text,18))
    b:SetClickMethod(1)
    local ctrl={kind="button",widget=b,action=action,accent=accent}
    S.controls[#S.controls+1]=ctrl
    return b,ctrl
end
local function message(text)
    S.message=tostring(text)
    if valid(S.status) then settext(S.status,S.message) end
    print("[RoweMenu] "..S.message)
end
local build_page
local function release_page(capture)
    -- Drop native widget references while the page still owns its children.
    if S.api.unmount then S.api.unmount(capture~=false) end
    S.controls={};S.status=nil
end
local function change_page(page)
    S.page=page;S.message=nil; S.rebuild=true
end
local function pretty(value)
    if type(value)=="boolean" then return value and "ON" or "OFF" end
    return type(value)=="number" and string.format("%.3g",value) or "Unavailable"
end
local function invoke(control)
    local now=os.clock()
    if S.lastAction and now-S.lastAction<.18 then return end
    S.lastAction=now
    control.action()
end
local function setting(parent,item)
    local key,title=item[1],item[2]
    local value=S.api.get(key)
    local row=construct("HorizontalBox",parent)
    local sized=box(parent,52); sized:SetContent(row); vadd(parent,sized,2)
    hadd(row,label(row,title,19),true)
    if value==nil then hadd(row,label(row,"Load a park to edit",16,C.muted)); return end
    if item[3]=="bool" then
        local b,ctrl
        b,ctrl=button(row,pretty(value),function()
            local nextValue=not S.api.get(key)
            S.api.set(key,nextValue)
            settext(ctrl.text,pretty(nextValue))
        end)
        ctrl.text=b:GetContent()
        local w=box(row,nil,130);w:SetContent(b);hadd(row,w)
    else
        local min,max=item[3],item[4]
        local slide=construct("Slider",row)
        slide:SetMinValue(min);slide:SetMaxValue(max);slide:SetStepSize(item[5])
        slide:SetValue(math.max(min,math.min(max,value)))
        slide:SetSliderHandleColor(C.yellow);slide:SetSliderBarColor(C.muted)
        local holder=box(row,nil,230);holder:SetContent(slide);hadd(row,holder)
        local text=label(row,limits.in_range(item,value) and limits.format(item,value) or "RESET",17,C.yellow)
        local width=box(row,nil,115);width:SetContent(text);hadd(row,width)
        pcall(function() slide:SetToolTipText(FText((item.hint or "").." Range: "..
            limits.format(item,min).." - "..limits.format(item,max)..". Stock: "..limits.format(item,item.default))) end)
        S.controls[#S.controls+1]={kind="slider",widget=slide,text=text,key=key,
            min=min,max=max,step=item[5],item=item,last=slide:GetValue(),applied=value}
    end
    local reset=button(row,"RESET",function()
        S.api.reset(key);S.rebuild=true;message(title.." reset")
    end)
    local w=box(row,nil,100);w:SetContent(reset);hadd(row,w)
end
build_page=function()
    release_page(true);S.selected=1
    S.content:ClearChildren()
    local header=construct("HorizontalBox",S.content)
    hadd(header,label(header,"ROWEMOD",34,C.yellow),true)
    hadd(header,button(header,"CLOSE  /  F5",function() M.close() end))
    vadd(S.content,header)
    vadd(S.content,label(S.content,"MAKE IT FEEL LIKE YOU",14,C.muted))
    local tabs=construct("HorizontalBox",S.content)
    for _,p in ipairs({"Movement","Tricks","Balance","Multiplayer"}) do
        hadd(tabs,button(tabs,p:upper(),function() change_page(p) end,S.page==p),true)
    end
    vadd(S.content,tabs,6)
    if S.page=="Multiplayer" then
        if S.api.multiplayer then S.api.multiplayer(M,S.content) end
    else
        for _,group in ipairs(schema) do
            if group.id==S.page then
                for _,item in ipairs(group.items) do setting(S.content,item) end
            end
        end
        local actions=construct("HorizontalBox",S.content)
        hadd(actions,button(actions,"SAVE SETTINGS",function()
            local ok,err=S.api.save(); message(ok and "Settings saved for the next launch" or ("Save failed: "..tostring(err)))
        end,true),true)
        hadd(actions,button(actions,"RESET THIS PAGE",function()
            for _,group in ipairs(schema) do if group.id==S.page then
                for _,item in ipairs(group.items) do S.api.reset(item[1]) end
            end end
            S.rebuild=true;message("Page reset. Save to keep these settings.")
        end),true)
        vadd(S.content,actions,8)
    end
    S.status=label(S.content,S.message or (S.page=="Multiplayer" and "Join a session to follow the host's park automatically." or "Changes apply live. Save to keep them."),15,C.muted)
    S.status:SetAutoWrapText(true);vadd(S.content,S.status,8)
    vadd(S.content,label(S.content,"F5 close   /   Mouse or arrows + Enter   /   D-pad + A",13,C.muted))
    S.click=false;S.rebuild=false
end
function M.close(discard)
    if not S.open then return end
    release_page(not discard)
    S.open=false
    if valid(S.root) then S.root:SetVisibility(1) end
    local pc=S.pc
    if valid(pc) then
        pc.bShowMouseCursor=S.cursor or false
        if S.ignoreMove then pc:SetIgnoreMoveInput(false) end
        if S.ignoreLook then pc:SetIgnoreLookInput(false) end
        local lib=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        if not S.cursor then lib:SetInputMode_GameOnly(pc,false) end
    end
    S.ignoreMove=false;S.ignoreLook=false;S.click=false
    print("[RoweMenu] closed")
end
local function open_menu()
    if S.open then return end
    S.pc=helpers.GetPlayerController()
    if not valid(S.pc) then return end
    local world=helpers.GetWorld()
    if not valid(world) then return end
    if valid(S.root) and S.world and S.world~=world:GetAddress() then
        release_page(false)
        S.root:RemoveFromParent();S.root=nil
    end
    if not valid(S.root) then
        S.font=StaticFindObject("/Game/MainFolder/UI/fonts/Quantico-BoldItalic_Font.Quantico-BoldItalic_Font")
        if not valid(S.font) and LoadAsset then S.font=LoadAsset("/Game/MainFolder/UI/fonts/Quantico-BoldItalic_Font.Quantico-BoldItalic_Font") end
        local outer=helpers.GetGameInstance()
        S.root=construct("UserWidget",outer)
        local tree=construct("WidgetTree",S.root);S.root.WidgetTree=tree
        local canvas=construct("CanvasPanel",tree);tree.RootWidget=canvas
        local border=construct("Border",canvas);border:SetBrushColor(C.panel)
        border:SetPadding({Left=24,Top=20,Right=24,Bottom=20})
        local scroll=construct("ScrollBox",border);border:SetContent(scroll);S.scroll=scroll
        S.content=construct("VerticalBox",scroll);scroll:AddChild(S.content)
        local slot=canvas:AddChildToCanvas(border)
        slot:SetAnchors({Minimum={X=.15,Y=.07},Maximum={X=.85,Y=.93}})
        slot:SetOffsets({Left=0,Top=0,Right=0,Bottom=0})
        S.root:SetVisibility(1)
        S.root:AddToViewport(100)
    end
    build_page()
    S.root:SetVisibility(0)
    S.open=true
    S.cursor=S.pc.bShowMouseCursor
    S.pc.bShowMouseCursor=true
    S.pc:SetIgnoreMoveInput(true);S.ignoreMove=true
    S.pc:SetIgnoreLookInput(true);S.ignoreLook=true
    StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):SetInputMode_GameAndUIEx(S.pc,S.root,0,false,false)
    S.world=helpers.GetWorld():GetAddress()
    S.open=true
    print("[RoweMenu] opened "..S.page.." native_font="..tostring(valid(S.font)))
end
function M.open()
    local ok,err=pcall(open_menu)
    if not ok then
        pcall(M.close,true)
        release_page(false)
        if valid(S.root) then S.root:RemoveFromParent() end
        S.root=nil;S.content=nil
        print("[RoweMenu] open failed: "..tostring(err))
    end
end
function M.toggle() if S.open then M.close() else M.open() end end
function M.is_open() return S.open end
local function navigate(delta)
    if not S.open or #S.controls==0 then return end
    local old=S.controls[S.selected]
    if old and old.kind=="button" then
        old.widget:SetBackgroundColor(old.accent and C.purple or C.row)
        old.widget:GetContent():SetColorAndOpacity({SpecifiedColor=C.white,ColorUseRule=0})
    end
    S.selected=((S.selected-1+delta)%#S.controls)+1
    local ctrl=S.controls[S.selected]
    if ctrl.kind=="button" then
        ctrl.widget:SetBackgroundColor(C.yellow)
        ctrl.widget:GetContent():SetColorAndOpacity({SpecifiedColor=C.panel,ColorUseRule=0})
    end
    pcall(function() S.scroll:ScrollWidgetIntoView(ctrl.widget,true,0,12) end)
    pcall(function() ctrl.widget:SetKeyboardFocus() end)
end
local function activate(delta)
    if not S.open then return end
    local c=S.controls[S.selected]
    if not c then return end
    if c.kind=="slider" then
        c.widget:SetValue(math.max(c.min,math.min(c.max,c.last+(delta or 1)*c.step)))
    elseif not delta and c.action then invoke(c) end
end
local function tick()
    if not S.open then return end
    local world=helpers.GetWorld()
    if not valid(world) or world:GetAddress()~=S.world or not valid(S.root) then
        M.close(true);if valid(S.root) then S.root:RemoveFromParent() end;S.root=nil;return
    end
    if S.rebuild then build_page();return end
    local click=S.click;S.click=false
    for i,c in ipairs(S.controls) do
        if c.kind=="slider" then
            local value=c.widget:GetValue()
            if math.abs(value-c.last)>.000001 then
                value=limits.snap(c.item,value)
                if value then
                    c.widget:SetValue(value);c.last=c.widget:GetValue()
                    if math.abs(value-c.applied)>.000001 then S.api.set(c.key,value);c.applied=value end
                    settext(c.text,limits.format(c.item,value))
                end
            end
        elseif c.kind=="button" then
            local down=c.widget:IsPressed()
            if (click and c.widget:IsHovered()) or (down and not c.down) then
                c.down=down;S.selected=i;invoke(c);break
            end
            c.down=down
        end
    end
    if S.api.tick and S.open and not S.rebuild then S.api.tick(S.page) end
end
function M.init(api)
    S.api=api
    RegisterKeyBind(Key.F5,dispatch.wrap(M.toggle))
    RegisterKeyBind(Key.LEFT_MOUSE_BUTTON,function() if S.open then S.click=true end end)
    for key,fn in pairs({UP=function() navigate(-1) end,DOWN=function() navigate(1) end,
        LEFT=function() activate(-1) end,RIGHT=function() activate(1) end,
        RETURN=function() activate() end}) do
        if Key[key] then RegisterKeyBind(Key[key],dispatch.wrap(fn)) end
    end
    -- Engine gamepad polling stays on the same persistent native timer.
    local keys={Gamepad_DPad_Up=function() navigate(-1) end,Gamepad_DPad_Down=function() navigate(1) end,
        Gamepad_DPad_Left=function() activate(-1) end,Gamepad_DPad_Right=function() activate(1) end,
        Gamepad_FaceButton_Bottom=function() activate() end,Gamepad_FaceButton_Right=M.close}
    local previous={}
    dispatch.loop(33,function()
        if S.open then
            for key,fn in pairs(keys) do
                local ok,down=pcall(function() return S.pc:IsInputKeyDown({KeyName=FName(key)}) end)
                down=ok and down
                if down and not previous[key] then fn() end
                previous[key]=down
            end
        else previous={} end
        tick()
    end)
end
-- Small renderer API for the multiplayer page, sharing input and style.
M.button=button;M.label=label;M.vadd=vadd;M.hadd=hadd;M.construct=construct;M.settext=settext
M.message=message;M.rebuild=function() S.rebuild=true end
function M.card(parent,title,subtitle)
    local border=construct("Border",parent);border:SetBrushColor(C.row)
    border:SetPadding({Left=16,Top=12,Right=16,Bottom=12})
    local body=construct("VerticalBox",border);border:SetContent(body);vadd(parent,border,8)
    if title then vadd(body,label(body,title,22,C.white),4) end
    if subtitle then local text=label(body,subtitle,15,C.muted);text:SetAutoWrapText(true);vadd(body,text,4) end
    return body
end
function M.action(parent,title,fn,accent)
    local holder=box(parent,46);local control=button(holder,title,fn,accent)
    holder:SetContent(control);vadd(parent,holder,6)
end
function M.entry(parent,text)
    local e=construct("EditableTextBox",parent);settext(e,text or "")
    return e
end
return M
