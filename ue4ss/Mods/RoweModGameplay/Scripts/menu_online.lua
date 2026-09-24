-- A focused Join / Host menu. Steam startup and deferred requests run without UI.
local M={}
local root=(os.getenv("ROUEMOD_MP_ONLINE")=="1" and os.getenv("ROUEMOD_MP_MAILBOX"))
    or (require("mp.mailbox").default_dir().."/Steam")
local api,ui,status_label,name_field,id_field
local session_name,lobby_id="RoweMod session",""
local view,source,visibility="join","friends","friends"
local show_code,show_details=false,false
local initialized,starting,pending,failure,last_update,last_notice,signature
local snapshot={rows={},stale=true,message="Connecting to Steam..."}
local request_seq=0
local last_search=0
local copy_waiting
local player_widgets,room_widgets={},{}
local session_label
local label_text={}
local function set_label(w,text)
    if label_text[w]~=text then ui.settext(w,text);label_text[w]=text end
end
local function encode(value)
    return tostring(value or ""):gsub("[%%\t\r\n]",function(c) return string.format("%%%02X",c:byte()) end)
end
local function decode(value) return (value:gsub("%%(%x%x)",function(h) return string.char(tonumber(h,16)) end)) end
local function read_state()
    local f=io.open(root.."/menu_state.txt","rb")
    if not f then return {rows={},stale=true,message="Connecting to Steam..."} end
    local raw=f:read(65537);f:close()
    local state={rows={},roster={}}
    if not raw or #raw>65536 then state.stale=true;state.message="Steam status unavailable";return state end
    for line in raw:gmatch("[^\r\n]+") do
        local cells={}
        for cell in (line.."\t"):gmatch("(.-)\t") do cells[#cells+1]=decode(cell) end
        if cells[1]=="room" and #cells==6 then state.rows[#state.rows+1]=cells
        elseif cells[1]=="player" and #cells==7 and #state.roster<8 then state.roster[#state.roster+1]=cells
        elseif #cells==2 then state[cells[1]]=cells[2] end
    end
    if state.phase=="error" then state.stale=true;state.rows={}
    elseif not state.updated or os.time()-(tonumber(state.updated) or 0)>5 then
        state.stale=true;state.rows={};state.message="Steam disconnected. Retry to reconnect."
    end
    return state
end
local function ready(s) return not s.stale and (s.phase=="ready" or (not s.phase and s.role~=nil)) end
local function active(s) return ready(s) and s.lobby and s.lobby~="0" and (s.role=="host" or s.role=="join") end
local function say(text) if ui then ui.message(text) end end
local function rebuild() if ui then ui.rebuild() end end
local function send(action,fields)
    request_seq=request_seq+1
    local path=root.."/control/menu-"..os.time().."-"..string.format("%06d",request_seq)..".txt"
    local f=io.open(path..".tmp","wb")
    if not f then return false,"Unable to contact Steam. Retry the connection." end
    f:write("action\t"..encode(action).."\n")
    for k,v in pairs(fields or {}) do f:write(k.."\t"..encode(v).."\n") end
    f:close()
    if not os.rename(path..".tmp",path) then return false,"Unable to send the session request" end
    if action=="host" or action=="join" then api.connect() end
    if action=="diagnostics" then copy_waiting=os.time() end
    return true
end
local function launch()
    if starting then return end
    local ok,err=require("mp.online").open(nil,true)
    if ok then starting=os.time();failure=nil else failure=err;pending=nil end
end
local function request(action,fields)
    if snapshot.busy=="1" and action~="diagnostics" then say("Finishing the current session request...");return end
    pending={action=action,fields=fields};failure=nil;last_update=nil
    if not ready(read_state()) then launch() end
end
function M.init(callbacks) api=callbacks end
function M.unmount(capture)
    if capture then
        if name_field then session_name=name_field:GetText():ToString() end
        if id_field then lobby_id=id_field:GetText():ToString() end
    end
    name_field=nil;id_field=nil;status_label=nil;ui=nil;signature=nil;last_notice=nil
    player_widgets={};room_widgets={};session_label=nil;label_text={}
end
function M.update()
    if not initialized or last_update==os.time() then return end
    last_update=os.time();snapshot=read_state()
    if copy_waiting and (tonumber(snapshot.updated) or 0)>copy_waiting and
        (tostring(snapshot.message):match("^Diagnostics") or tostring(snapshot.message):match("^Clipboard")) then
        say(snapshot.message);copy_waiting=nil
    end
    if starting then
        if ready(snapshot) then starting=nil;api.connect()
        elseif snapshot.phase=="error" and (tonumber(snapshot.updated) or 0)>=starting then
            starting=nil;failure=snapshot.message;pending=nil
        elseif os.time()-starting>=30 then
            starting=nil;pending=nil;failure="Steam did not respond. Check Steam is running, then retry."
        end
    end
    if pending and ready(snapshot) then
        local job=pending;pending=nil
        if job.action=="friends" or job.action=="browse" then last_search=os.time() end
        local ok,err=send(job.action,job.fields)
        if not ok then failure=err end
    end
end
local function map_status() return api.map_status and api.map_status() or {phase="idle"} end
local function player_rows()
    local health=api.players and api.players() or {players={}}
    local byId={}
    if tostring(health.lobby)==tostring(snapshot.lobby) then
        for _,p in ipairs(health.players or {}) do byId[p.id]=p end
    end
    local rows={}
    for _,p in ipairs(snapshot.roster or {}) do
        local status=p[7]=="1" and "Waiting for game" or "Connecting"
        local badge=p[4]=="1" and "HOST" or "PLAYER"
        local map=p[6]
        if p[5]=="1" then
            badge=badge.." / YOU";status="Ready"
            local travel=map_status()
            if travel.phase=="loading" or travel.phase=="waiting" then status="Loading map"
            elseif travel.phase=="failed" then status="Map load failed" end
        elseif byId[p[2]] and p[7]=="1" then status=byId[p[2]].status;map=byId[p[2]].map end
        rows[#rows+1]={name=p[3]:gsub("[%c]"," "),badge=badge,status=status,map=map}
    end
    return rows
end
local function layout_signature()
    -- Only structural changes rebuild controls. Names, counts, parks and avatar
    -- health update existing labels without disturbing focus or text entry.
    local parts={active(snapshot) and (snapshot.role..":"..snapshot.lobby) or "browse",
        tostring(not not (failure or snapshot.stale and not starting)),
        tostring(active(snapshot) and map_status().phase=="failed")}
    if not active(snapshot) and view=="join" then
        for _,r in ipairs(snapshot.rows) do parts[#parts+1]=r[2] end
    end
    return table.concat(parts,"\n")
end
local function refresh_labels()
    if session_label then set_label(session_label,"Players: "..tostring(snapshot.players or "1").."   |   Park: "..tostring(snapshot.map or "Loading")) end
    local rows=player_rows()
    for i,w in ipairs(player_widgets) do
        local p=rows[i]
        local visibility=p and 4 or 1 -- self-hit-test-invisible / collapsed
        if w.visibility~=visibility then w.row:SetVisibility(visibility);w.visibility=visibility end
        if p then
            set_label(w.name,p.name.."   /   "..p.badge)
            set_label(w.status,p.status.."   |   "..(p.map=="unknown" and "Waiting for park" or p.map))
        end
    end
    for _,r in ipairs(snapshot.rows) do
        local w=room_widgets[r[2]]
        if w then set_label(w.name,r[3]);set_label(w.detail,r[4].."   |   "..r[5].." players") end
    end
end
local function switch(nextView) view=nextView;show_code=false;rebuild() end
function M.build(renderer,parent)
    ui=renderer
    if not initialized then
        initialized=true;snapshot=read_state()
        if ready(snapshot) then api.connect() end
        if not active(snapshot) then request("friends") end
    end
    local state=snapshot
    local status=ui.card(parent,"ONLINE",snapshot.version and ("RoweMod "..snapshot.version) or nil)
    status_label=ui.label(status,"Connecting...",17);ui.vadd(status,status_label,4)
    pcall(function() status_label:SetAutoWrapText(true) end)
    if failure or state.stale and not starting then
        ui.action(status,"RETRY CONNECTION",function() request(source);rebuild() end,true)
    end
    if active(state) then
        local card=ui.card(parent,state.role=="host" and "YOUR SESSION" or "SKATING TOGETHER",
            state.role=="host" and "Friends join you here. Changing parks brings them along." or "You follow the host's park automatically.")
        session_label=ui.label(card,"",18);ui.vadd(card,session_label,6)
        local travel=map_status()
        if travel.phase=="failed" then ui.action(card,"RETRY MAP LOAD",function() api.retry_map() end,true) end
        local players=ui.card(parent,"PLAYERS","Avatar status is shown from your game's point of view.")
        for i=1,8 do
            local row=ui.construct("VerticalBox",players);ui.vadd(players,row,0)
            local name=ui.label(row,"",17)
            pcall(function() name:SetAutoWrapText(true) end)
            ui.vadd(row,name,6)
            local detail=ui.label(row,"",15);ui.vadd(row,detail,4)
            player_widgets[i]={row=row,name=name,status=detail}
        end
        ui.action(card,show_details and "HIDE SESSION CODE" or "SHOW SESSION CODE",function() show_details=not show_details;rebuild() end)
        if show_details then ui.vadd(card,ui.label(card,tostring(state.lobby),18),6) end
        ui.action(card,"LEAVE SESSION",function() request("leave");api.disconnect() end)
    else
        local nav=ui.construct("HorizontalBox",parent)
        ui.hadd(nav,ui.button(nav,"JOIN",function() switch("join");request(source) end,view=="join"),true)
        ui.hadd(nav,ui.button(nav,"HOST",function() switch("host") end,view=="host"),true)
        ui.vadd(parent,nav,10)
        if view=="host" then
            local card=ui.card(parent,"HOST A SESSION","Choose a name and who can join. Your current park is shared automatically.")
            ui.vadd(card,ui.label(card,"Session name",16),6)
            name_field=ui.entry(card,session_name);ui.vadd(card,name_field,6)
            ui.action(card,visibility=="friends" and "VISIBILITY: FRIENDS ONLY" or "VISIBILITY: PUBLIC",function()
                visibility=visibility=="friends" and "public" or "friends";rebuild()
            end)
            ui.action(card,"HOST SESSION",function()
                session_name=name_field:GetText():ToString()
                request("host",{name=session_name,visibility=visibility})
            end,true)
        else
            local card=ui.card(parent,source=="friends" and "JOIN FRIENDS" or "PUBLIC SESSIONS","Choose a session. We'll connect and load the host's park.")
            local filters=ui.construct("HorizontalBox",card)
            ui.hadd(filters,ui.button(filters,source=="friends" and "SHOW PUBLIC" or "SHOW FRIENDS",function()
                source=source=="friends" and "browse" or "friends";snapshot.rows={};request(source);rebuild()
            end),true)
            ui.hadd(filters,ui.button(filters,"REFRESH",function() request(source) end),true)
            ui.vadd(card,filters,8)
            for _,r in ipairs(state.rows) do
                local room=ui.card(card)
                local name=ui.label(room,r[3],22);ui.vadd(room,name,4)
                local detail=ui.label(room,r[4].."   |   "..r[5].." players",15);ui.vadd(room,detail,4)
                room_widgets[r[2]]={name=name,detail=detail}
                ui.action(room,"JOIN SESSION",function() request("join",{lobby=r[2]}) end,true,"join:"..r[2])
            end
            if #state.rows==0 then ui.vadd(card,ui.label(card,starting and "Connecting to Steam..." or "No sessions found yet.",16),12) end
            ui.action(card,show_code and "HIDE SESSION CODE" or "JOIN WITH A CODE",function() show_code=not show_code;rebuild() end)
            if show_code then
                id_field=ui.entry(card,lobby_id);ui.vadd(card,id_field,6)
                ui.action(card,"JOIN CODE",function()
                    lobby_id=id_field:GetText():ToString()
                    local value=lobby_id:match("^%s*(%d+)%s*$")
                    if not value or #value>20 then say("Enter a numeric session code");return end
                    request("join",{lobby=value})
                end,true)
            end
        end
    end
    local support=ui.card(parent,"HELP","Copies connection and avatar details without account IDs or the session code.")
    ui.action(support,"COPY DIAGNOSTICS",function() request("diagnostics");say("Preparing diagnostics...") end)
    refresh_labels();signature=layout_signature();last_notice=nil
end
function M.tick(page)
    M.update()
    if page~="Multiplayer" or not ui then return end
    if ready(snapshot) and not active(snapshot) and view=="join" and not show_code and not pending and snapshot.busy~="1" and os.time()-last_search>=10 then request(source) end
    local text=failure or snapshot.message or "Ready"
    local travel=map_status()
    if text:match("^Diagnostics") or text:match("^Clipboard") then -- Keep the copy result visible.
    elseif active(snapshot) and snapshot.role=="join" and travel.message then text=travel.message
    elseif starting then text="Connecting to Steam... ("..tostring(os.time()-starting).."s)"
    elseif ready(snapshot) and not active(snapshot) then text="Steam ready. "..tostring(snapshot.message or "Choose a session or host your own.") end
    if pending and not starting then text="Connecting to your session..." end
    if status_label then set_label(status_label,text) end
    last_notice=text
    local nextSignature=layout_signature()
    if signature~=nextSignature then signature=nextSignature;rebuild()
    else refresh_labels() end
end
return M
