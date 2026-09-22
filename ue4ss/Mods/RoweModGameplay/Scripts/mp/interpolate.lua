-- Small delayed pose buffer. No prediction: a missing packet cannot send a
-- skater through the park. Quaternions take the shortest path across +/-180.
local M = {}
local function transform(a,b,t)
    local r={}
    for i=1,10 do r[i]=a[i]+(b[i]-a[i])*t end
    local dot=0; for i=4,7 do dot=dot+a[i]*b[i] end
    local sign=dot<0 and -1 or 1
    local norm=0
    for i=4,7 do r[i]=a[i]+(sign*b[i]-a[i])*t; norm=norm+r[i]*r[i] end
    norm=math.sqrt(norm)
    for i=4,7 do r[i]=r[i]/norm end
    return r
end
function M.blend(a,b,t)
    if t<=0 then return a end
    if t>=1 then return b end
    local poses={}
    for i,p in ipairs(a[3]) do
        local nextPose=b[3][i]
        local bones={}
        for j,v in ipairs(p[2]) do bones[j]=transform(v,nextPose[2][j],t) end
        poses[i]={transform(p[1],nextPose[1],t),bones}
    end
    return {1,b[2],poses}
end
function M.push(slot,frame,now)
    local q=slot.samples or {}; slot.samples=q
    local last=q[#q]
    if last then
        local a,b=last.frame[3][1][1],frame[3][1][1]
        local d=0; for i=1,3 do d=d+(a[i]-b[i])^2 end
        if d>1200^2 or now-last.time>.5 then q={}; slot.samples=q end
    end
    -- A mailbox poll may contain several packets. Keep the newest at that time.
    if q[#q] and now<=q[#q].time then table.remove(q) end
    q[#q+1]={time=now,frame=frame}
    while #q>8 do table.remove(q,1) end
end
function M.sample(slot,now,delay)
    local q=slot.samples
    if not q or #q==0 then return nil end
    local target=now-(delay or .12)
    while #q>2 and q[2].time<=target do table.remove(q,1) end
    if target<=q[1].time then return q[1].frame,q[1].time end
    for i=2,#q do
        if target<q[i].time then
            local a,b=q[i-1],q[i]
            return M.blend(a.frame,b.frame,(target-a.time)/(b.time-a.time)),target
        end
    end
    return q[#q].frame,q[#q].time
end
return M
