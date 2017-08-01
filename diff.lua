local pairs = pairs
local type = type

local function diff(base_t, new_t, patch_t)
    -- check base table
    for k, bv in pairs(base_t) do
        local nv = new_t[k]
        local nv_t = type(nv)
        local bv_t = type(bv)
        -- delete key
        if nv_t=="nil" then
            patch_t[k] = "__NIL_VALUE__"
        
        -- diff next table
        elseif bv_t=="table" and nv_t=="table" then
            patch_t[k] = {}
            diff(bv, nv, patch_t[k])
        
        -- modify key
        elseif bv~=nv then
            patch_t[k] = nv
        end
    end

    -- check new table
    for k, nv in pairs(new_t) do
        local bv = base_t[k]
        local nv_t = type(nv)
        local bv_t = type(bv)

        -- new key
        if bv_t=="nil" then
            patch_t[k] = nv
        end
    end

    return patch_t
end


return function (base_t, new_t)
    return diff(base_t, new_t, {})
end

