-- Bounded data-only codec: dense arrays, finite numbers, and escaped strings.
-- No load/eval, executable values, or UObject references cross the connection.
local M = {MAX_BYTES=524288}
function M.encode(value)
    local out={}
    local function put(v,depth)
        assert(depth<=12,"payload depth")
        if type(v)=="table" then
            assert(#v<=4096,"array size")
            out[#out+1]="a"..#v..":"
            for _,child in ipairs(v) do put(child,depth+1) end
        elseif type(v)=="number" then
            assert(v==v and math.abs(v)<1e12,"nonfinite/out of range number")
            out[#out+1]="n"..string.format("%.7g",v)..";"
        elseif type(v)=="string" then
            local s=v:gsub("[%%\r\n]",function(c) return string.format("%%%02X",c:byte()) end)
            assert(#s<=2048,"string size")
            out[#out+1]="s"..#s..":"..s
        else error("unsupported payload type") end
    end
    put(value,0)
    local s=table.concat(out); assert(#s<=M.MAX_BYTES,"payload size"); return s
end
function M.decode(s)
    if type(s)~="string" or #s>M.MAX_BYTES then return nil end
    local pos,nodes=1,0
    local function take(depth)
        nodes=nodes+1; assert(nodes<=60000 and depth<=12,"payload limits")
        local kind=s:sub(pos,pos); pos=pos+1
        if kind=="n" then
            local e=assert(s:find(";",pos,true)); assert(e-pos<=24)
            local n=assert(tonumber(s:sub(pos,e-1))); pos=e+1
            assert(n==n and math.abs(n)<1e12); return n
        end
        assert(kind=="a" or kind=="s")
        local e=assert(s:find(":",pos,true)); assert(e-pos<=6)
        local count=s:sub(pos,e-1); assert(count:match("^%d+$")); count=tonumber(count); pos=e+1
        if kind=="s" then
            assert(count<=2048 and pos+count-1<=#s)
            local v=s:sub(pos,pos+count-1); pos=pos+count
            return (v:gsub("%%(%x%x)",function(h) return string.char(tonumber(h,16)) end))
        end
        assert(count<=4096)
        local a={}; for i=1,count do a[i]=take(depth+1) end; return a
    end
    local ok,v=pcall(take,0)
    if ok and pos==#s+1 then return v end
end
return M
