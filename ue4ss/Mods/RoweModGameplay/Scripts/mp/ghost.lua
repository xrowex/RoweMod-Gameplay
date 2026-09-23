-- Passive remote renderers. A peer can only update its own avatar slot.
local avatar = require("mp.avatar")
local interpolate = require("mp.interpolate")
local M = {}
function M.create_manager()
    local self = {ghosts={}, lastSeq={}, retryAfter={}}
    function self:ensure(peerId, name)
        local s=self.ghosts[peerId]
        if s then s.displayName=name or s.displayName end
        return s
    end
    function self:apply_frame(peerId, msg)
        if msg.seq <= (self.lastSeq[peerId] or -1) then return false end
        avatar.validate(msg.frame)
        self.lastSeq[peerId]=msg.seq
        local key=avatar.geometry_key(msg.frame)
        local s=self.ghosts[peerId]
        if not s or not s.actor:IsValid() or s.key~=key then
            if os.time() < (self.retryAfter[peerId] or 0) then return false end
            local ok,fresh=pcall(avatar.spawn,msg.frame)
            if not ok then
                self.retryAfter[peerId]=os.time()+3
                error(fresh)
            end
            self.retryAfter[peerId]=nil
            self:remove(peerId, true)
            fresh.key=key
            self.ghosts[peerId]=fresh
            s=fresh
            print("[RoweModMP] remote avatar "..peerId.." parts="..#s.parts)
        else avatar.update_materials(s,msg.frame) end
        interpolate.push(s,msg.frame,os.clock())
        s.lastSeen=os.time()
        local t=msg.frame[3][1][1]
        s.last={x=t[1],y=t[2],z=t[3]}
        s.frames=(s.frames or 0)+1
        return true
    end
    function self:render(now)
        local started=os.clock()
        for peer,s in pairs(self.ghosts) do
            local ok,err=pcall(function()
                if s.actor:IsValid() then
                    local frame,stamp=interpolate.sample(s,now)
                    if frame and stamp~=s.renderStamp then
                        avatar.apply(s,frame)
                        s.renderStamp=stamp
                        s.renders=(s.renders or 0)+1
                        s.lastRendered=os.time()
                    end
                end
            end)
            if not ok then
                local message=tostring(err)
                if s.renderError~=message then print("[RoweModMP] render "..peer..": "..message) end
                s.renderError=message
            else s.renderError=nil end
        end
        local elapsed=(os.clock()-started)*1000
        self.renderMs=self.renderMs and self.renderMs*.9+elapsed*.1 or elapsed
    end
    function self:remove(peerId, keepSequence)
        local s=self.ghosts[peerId]
        if s and s.actor and s.actor:IsValid() then s.actor:K2_DestroyActor() end
        self.ghosts[peerId]=nil
        if not keepSequence then self.lastSeq[peerId]=nil; self.retryAfter[peerId]=nil end
    end
    function self:clear()
        for id in pairs(self.ghosts) do self:remove(id) end
        self.lastSeq={}
        self.retryAfter={}
    end
    return self
end
return M
