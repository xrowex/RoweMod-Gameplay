-- The windowless helper checks releases outside the game process.
local M={}
function M.check()
    for _,path in ipairs({"RoweModOnline/RoweModOnline.exe","../RoweModOnline/RoweModOnline.exe"}) do
        local f=io.open(path,"rb")
        if f then
            f:close()
            os.execute('start "" /B "'..path..'" --check-updates')
            return true
        end
    end
    return false
end
return M
