-- Deduplicate host requests; acknowledge arrival, never just an OpenLevel call.
local mapinfo=require("mp.mapinfo")
local M={}
function M.new(load,ack)
    local t={phase="idle"}
    function t:request(want,current,pawnReady,retry)
        want=mapinfo.normalize(want)
        if self.phase=="loading" and want~=self.target then self.queued=want;return end
        if want==self.target and not retry and (self.phase=="loading" or self.phase=="failed") then return end
        self.target=want;self.queued=nil
        if mapinfo.is_menu(want) then self.phase="waiting";self.message="Waiting for the host to load a park";return end
        if mapinfo.same(current,want) and pawnReady then
            self.phase="ready";self.message="In the host's park";ack(current,true);return
        end
        self.phase="loading";self.started=os.time();self.message="Loading "..want.."..."
        if mapinfo.same(current,want) then return end
        local ok,detail=load(want)
        if not ok then self.phase="failed";self.message=detail;ack(current,false) end
    end
    function t:update(current,pawnReady)
        if self.phase~="loading" then return end
        if mapinfo.same(current,self.target) and pawnReady then
            self.phase="ready";self.message="In the host's park";ack(current,true)
            if self.queued then local nextMap=self.queued;self.queued=nil;self:request(nextMap,current,pawnReady) end
        elseif os.time()-self.started>=60 then
            self.phase="failed";self.message="Could not finish loading "..self.target..". Retry loading the host's park.";ack(current,false)
        end
    end
    return t
end
return M
