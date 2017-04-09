local print_r = require "print_r"
local encode = require "encode"
local decode = require "decode"

local source = {
    aa = 11, 
    bb = "test_string",
    cc = {
        11, 22, 33, 44, "cc_string",
        {55, 66, true},
    },

    dd = false,
    [1] = nil,
    [2] = {},
    [3] = {11, nil, 44},
}

source[1] = source

local function write_file(file, s)
    local handle = io.open(file, "wb")
    handle:write(s)
    handle:close()
end


local function dump_hex(s, len)
    len = len or #s
    print(string.format("--------- dump_hex[%d] ---------", len))
    len = math.min(len, #s)
    local t = {}
    for i=1, len do
        local c = string.byte(s, i)
        if (i-1)%16 == 0 then
            t[#t+1] = "\n"
        end
        t[#t+1] = string.format("%.2X ", c)
    end
    print(table.concat(t))
end

local s = encode(source)
dump_hex(s)

local data_file = "t.dat"
write_file(data_file, s)

local ts_obj = decode(data_file)
print_r(ts_obj)
