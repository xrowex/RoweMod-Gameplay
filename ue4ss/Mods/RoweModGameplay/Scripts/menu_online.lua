local M = {}
local root = (os.getenv("ROUEMOD_MP_ONLINE") == "1" and os.getenv("ROUEMOD_MP_MAILBOX"))
    or (require("mp.mailbox").default_dir() .. "/Steam")
local name_field, id_field
local session_name, lobby_id = "RoweMod session", ""
local api, ui, status_label, rooms, last_state, last_poll
local request_seq=0
local function encode(text)
    return tostring(text or ""):gsub("[%%\t\r\n]",function(c) return string.format("%%%02X",c:byte()) end)
end
local function decode(text)
    return (text:gsub("%%(%x%x)",function(h) return string.char(tonumber(h,16)) end))
end
local function read_state()
    local f=io.open(root.."/menu_state.txt","rb")
    if not f then return {message="Start Steam connection to host or browse sessions",rows={}} end
    local raw=f:read(65537);f:close()
    if not raw or #raw>65536 then return {message="Session status unavailable",rows={}} end
    local result={rows={},raw=raw}
    for line in raw:gmatch("[^\r\n]+") do
        local cells={}
        for cell in (line.."\t"):gmatch("(.-)\t") do cells[#cells+1]=decode(cell) end
        if cells[1]=="room" and #cells==6 then result.rows[#result.rows+1]=cells
        elseif #cells==2 then result[cells[1]]=cells[2] end
    end
    if not result.updated or os.time()-(tonumber(result.updated) or 0)>5 then
        result.message="Steam companion is closed. Start Steam connection."
        result.rows={};result.stale=true
    end
    return result
end
local function request(action,fields)
    request_seq=request_seq+1
    local path=root.."/control/menu-"..os.time().."-"..string.format("%06d",request_seq)..".txt"
    local f,err=io.open(path..".tmp","wb")
    if not f then ui.message("Start Steam connection first");return false end
    f:write("action\t"..encode(action).."\n")
    for k,v in pairs(fields or {}) do f:write(k.."\t"..encode(v).."\n") end
    f:close()
    local ok=os.rename(path..".tmp",path)
    if not ok then ui.message("Could not send session request");return false end
    if action=="host" or action=="join" then api.connect() end
    ui.message("Request sent: "..action)
    return true
end
function M.init(callbacks) api=callbacks end
function M.build(renderer,parent)
    if name_field and name_field:IsValid() then session_name=name_field:GetText():ToString() end
    if id_field and id_field:IsValid() then lobby_id=id_field:GetText():ToString() end
    ui=renderer
    status_label=ui.label(parent,"Steam connection",19)
    ui.vadd(parent,status_label,8)
    local top=ui.construct("HorizontalBox",parent)
    ui.hadd(top,ui.button(top,"START STEAM CONNECTION",function()
        local ok,err=require("mp.online").open(nil,true)
        if ok then api.connect();ui.message("Steam connection starting...") else ui.message(err) end
    end,true),true)
    ui.hadd(top,ui.button(top,"LEAVE SESSION",function() request("leave");api.disconnect() end),true)
    ui.vadd(parent,top,6)
    local host=ui.construct("HorizontalBox",parent)
    local name=ui.entry(host,session_name);name_field=name;ui.hadd(host,name,true)
    ui.hadd(host,ui.button(host,"HOST FRIENDS",function() request("host",{name=name:GetText():ToString(),visibility="friends"}) end))
    ui.hadd(host,ui.button(host,"HOST PUBLIC",function() request("host",{name=name:GetText():ToString(),visibility="public"}) end))
    ui.vadd(parent,host,6)
    local browse=ui.construct("HorizontalBox",parent)
    ui.hadd(browse,ui.button(browse,"FIND FRIENDS",function() request("friends") end),true)
    ui.hadd(browse,ui.button(browse,"PUBLIC SESSIONS",function() request("browse") end),true)
    ui.vadd(parent,browse,6)
    local direct=ui.construct("HorizontalBox",parent)
    ui.hadd(direct,ui.label(direct,"Lobby ID",18))
    local id=ui.entry(direct,lobby_id);id_field=id;ui.hadd(direct,id,true)
    ui.hadd(direct,ui.button(direct,"JOIN ID",function()
        local value=id:GetText():ToString():match("^%s*(%d+)%s*$")
        if not value or #value>20 then ui.message("Enter a numeric lobby ID");return end
        request("join",{lobby=value})
    end))
    ui.vadd(parent,direct,6)
    local state=read_state()
    last_state=state.raw
    for _,r in ipairs(state.rows) do
        local row=ui.construct("HorizontalBox",parent)
        ui.hadd(row,ui.label(row,r[3].."  /  "..r[4].."  /  "..r[5],17),true)
        ui.hadd(row,ui.button(row,"JOIN",function() request("join",{lobby=r[2]}) end))
        ui.vadd(parent,row,3)
    end
    if #state.rows==0 then ui.vadd(parent,ui.label(parent,"Search for friends or public sessions above.",16),6) end
    ui.vadd(parent,ui.label(parent,"Both skaters need the same map and matching mod version.",15),6)
    last_poll=nil
end
function M.tick(page)
    if page~="Multiplayer" or not ui or os.time()==last_poll then return end
    last_poll=os.time()
    local state=read_state()
    local headline=tostring(state.message or "Steam ready")
    if state.role and not state.stale then
        headline=headline.."\n"..state.role:upper().."  |  Players: "..tostring(state.players or "0")..
            "  |  Map: "..tostring(state.map or "?").."  |  Lobby: "..tostring(state.lobby or "0")
    end
    if status_label then ui.settext(status_label,headline) end
    -- Rebuild only when the browser rows change, not on packet counters/timestamps.
    local signature={}
    for _,row in ipairs(state.rows) do signature[#signature+1]=table.concat(row,"|") end
    signature=table.concat(signature,"\n")
    if rooms and rooms~=signature then ui.rebuild() end
    rooms=signature
end
return M
