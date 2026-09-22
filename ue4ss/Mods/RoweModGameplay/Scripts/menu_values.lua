-- Shared validation for mouse/controller edits, presets and the gameplay API.
local M = {items={}}
for _,group in ipairs(require("menu_schema")) do
    for _,item in ipairs(group.items) do M.items[item[1]]=item end
end
function M.finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
function M.in_range(item,value)
    return M.finite(value) and value>=item[3] and value<=item[4]
end
function M.snap(item,value)
    if not M.finite(value) then return nil end
    value=math.max(item[3],math.min(item[4],value))
    local steps=math.floor((value-item[3])/item[5]+0.5+1e-7)
    return tonumber(string.format("%.8f",math.max(item[3],math.min(item[4],item[3]+steps*item[5]))))
end
function M.format(item,value)
    if not M.finite(value) then return "Unavailable" end
    return string.format(item.format or "%.2f",value*(item.scale or 1))
end
return M
