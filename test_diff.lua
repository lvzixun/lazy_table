local print_r = require "print_r"
local diff = require "diff"

local lzt_encode = require "encode"
local lzt_decode = require "decode"

local function write_file(file, s)
    local handle = io.open(file, "wb")
    handle:write(s)
    handle:close()
end

local function write_lzt(file, t)
    local s = lzt_encode(t)
    write_file(file, s)
end

local function check_table(t1, t2)
    for k,v1 in pairs(t1) do
        local v2 = t2[k]
        if type(v1)=="table" and type(v2)=="table" then
            check_table(v1, v2)
        elseif v1~=v2 then
            return false
        end
    end

    for k,v2 in pairs(t2) do
        if t1[k]==nil then
            return false
        end
    end
    return true
end


local base_table = {
    aa = 11, 
    bb = "test_string",
    cc = {
        11, 22, 33, 44, "cc_string",
        {55, 66, true},
    },

    dd = false,
    gg = {77, 88, 99, {"test_gg"}},
    [1] = nil,
    [2] = {name = "foo"},
    [3] = {"test_string", "aa",  nil, 44},
}


local new_table = {
    aa = 22,
    ff = "test_new",
    gg = true,
    hh = false,
    jj = 44,
    [2] = {{kk = 8}},
    cc = {
        22, 77, 44, "new_cc_string",
        {inside = "hello"},
    },
    ee = {test = "ff"},
}

local patch_table = diff(base_table, new_table)

write_lzt("base.lzt", base_table)
write_lzt("patch.lzt", patch_table)

local patch_obj = lzt_decode("patch.lzt")
local new_obj = lzt_decode("base.lzt", patch_obj)

print("----- patch table ------")
print_r(patch_obj)

print("\n----- new   obj ------")
print_r(new_obj)


print("\n----- new   table ------")
print_r(new_table)

local ok = check_table(new_obj, new_table)
print("\n---- check_table -----\n", ok)