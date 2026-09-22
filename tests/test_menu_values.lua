package.path="ue4ss/Mods/RoweModGameplay/Scripts/?.lua;"..package.path
local values=require("menu_values")
for key,item in pairs(values.items) do
    if item[3]~="bool" then
        assert(values.in_range(item,item.default),key.." stock value outside range")
        assert(values.snap(item,item.default)==item.default,key.." stock value off step grid")
        assert(values.snap(item,item[3])==item[3] and values.snap(item,item[4])==item[4])
        assert(values.snap(item,0/0)==nil and values.snap(item,math.huge)==nil)
        assert(values.snap(item,-math.huge)==nil and values.snap(item,"1")==nil)
        assert(values.snap(item,item[4]+10000)==item[4])
    end
end
assert(values.format(values.items.grindMagnetStrength,0.8)=="80%")
assert(values.format(values.items.speedMultiplier,1.25)=="1.25x")
assert(values.snap(values.items.jumpPrepSteering,0)==1,'Steering denominator must never reach zero')
assert(values.items.maxSpinSpeed==nil and values.items.balanceDriftIncrease==nil)
print("Audited ranges, stock defaults, step grid, units and finite-number validation passed")
