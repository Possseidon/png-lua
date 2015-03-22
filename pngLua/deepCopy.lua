--Taken from:
--http://stackoverflow.com/questions/640642/how-do-you-copy-a-lua-table-by-value

local function copy(obj, seen)
    if type(obj) ~= 'table' then 
        return obj 
    elseif seen and seen[obj] then 
        return seen[obj] 
    else
        local s = seen or {}
        local res = setmetatable({}, getmetatable(obj))
        s[obj] = res
        for k, v in pairs(obj) do 
            res[copy(k, s)] = copy(v, s) 
        end
        return res
    end
end

return copy