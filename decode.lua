local wire_type = require "wire_type"

local type = type
local assert = assert

local reader_mt = {}
reader_mt.__index = reader_mt

local index_new = nil
------------------ reader ------------------
local function check_file_handle(file_handle)
    assert(file_handle, "need file handle")
    assert(file_handle.seek, "need seek function")
    assert(file_handle.read, "need read function")
end

local function reader_new(file_handle)
    local raw = {
        v_file_handle = false,
        v_cache = setmetatable({}, {__mode = "kv"})
    }
    if type(file_handle)=="string" then
        raw.v_file_handle = io.open(file_handle, "rb")
    else
        raw.v_file_handle = file_handle
    end
    check_file_handle(raw.v_file_handle)
    return setmetatable(raw, reader_mt)
end

local function read_type(self)
    local s = self.v_file_handle:read(1)
    local v = string.unpack("<I1", s)
    -- print("read_type size: 1 value:"..(v))
    return v
end

local function read_string(self)
    local sz_s = self.v_file_handle:read(2)
    local sz = string.unpack("<I2", sz_s)
    local s = self.v_file_handle:read(sz)
    -- print("read_string size: "..(sz+2).." value:"..s)
    return s
end

local function read_integer_number(self)
    local s = self.v_file_handle:read(8)
    local v = string.unpack("<I8", s)
    -- print("read_integer size: 8 value:"..(v))
    return v
end

local function read_real_number(self)
    local s = self.v_file_handle:read(8)
    local v = string.unpack("d", s)
    -- print("read_real size: 8 value:"..(v))
    return v
end

local function read_offset(self)
    local s = self.v_file_handle:read(4)
    local v = string.unpack("<I4", s)
    -- print("read_offset size: 4 value:"..(v))
    return v
end

local function read_offset_value(self, pos, patch_table)
    local v = self.v_cache[pos]
    if v then
        return v
    else
        local cur_pos = self.v_file_handle:seek("cur")
        self.v_file_handle:seek("set", pos)
        local type, v = self:read_value(patch_table)
        assert(type~=wire_type.OFFSET_WIRE_TYPE)
        self.v_file_handle:seek("set", cur_pos)
        return v
    end
end


local valid_value_wire_type = {
    [wire_type.OFFSET_WIRE_TYPE] = true,
    [wire_type.NIL_WIRE_TYPE] = true,
    [wire_type.TRUE_WIRE_TYPE] = true,
    [wire_type.FALSE_WIRE_TYPE] = true,
}
local function set_value(type, v)
    if not valid_value_wire_type[type] then
        error("invalid value wire type: "..tostring(type))
    end
    return v
end

local function set_key(self, wtype, v)
    if wtype == wire_type.OFFSET_WIRE_TYPE then
        v = read_offset_value(self, v)
        local tv = type(v)
        if tv == "nil" or tv == "table" then
            error("invalid key type:"..tostring(key))
        end
    end
    return v
end

local function set_patch(patch_table, t)
    if patch_table then
        for k,v in pairs(patch_table) do
            if v=="__NIL_VALUE__" then
                t[k] = nil
            elseif t[k]==nil then
                t[k] = "__NEW_VALUE__"
            end
        end
    end
end

local function read_list(self, patch_table)
    local list = {}
    local s = self.v_file_handle:read(4)
    local entry_len = string.unpack("<I4", s)
    -- print("read list entry_len:"..(entry_len))
    for i=1,entry_len do
        local type, v = self:read_value()
        list[i] = set_value(type, v)
    end
    set_patch(patch_table, list)
    return index_new(list, self, patch_table)
end


local function read_map(self, patch_table)
    local map = {}
    local s = self.v_file_handle:read(4)
    local entry_len = string.unpack("<I4", s)
    -- print("read map entry_len:"..(entry_len))
    for i=1,entry_len do
        local tk, vk = self:read_value()
        local tv, vv = self:read_value()
        local key = set_key(self, tk, vk)
        local value = set_value(tv, vv)
        assert(map[key]==nil)
        map[key] = value
    end
    set_patch(patch_table, map)
    return index_new(map, self, patch_table)
end


local type_drive_map = {
    [wire_type.NIL_WIRE_TYPE] = function (self)
        return nil
    end,

    [wire_type.MAP_WIRE_TYPE] = read_map,

    [wire_type.LIST_WIRE_TYPE] = read_list,

    [wire_type.STRING_WIRE_TYPE] = read_string,

    [wire_type.REAL_WIRE_TYPE] = read_real_number,

    [wire_type.INTEGET_WIRE_TYPE] = read_integer_number,

    [wire_type.TRUE_WIRE_TYPE] = function() 
        return true 
    end,

    [wire_type.FALSE_WIRE_TYPE] = function ()
        return false
    end,

    [wire_type.OFFSET_WIRE_TYPE] = read_offset,
}


function reader_mt:read_value(patch_table)
    local cur_pos = self.v_file_handle:seek("cur")
    local type = read_type(self)
    local f = type_drive_map[type]
    if not f then
        error("invalid type:"..tostring(type))
    end
    local v = f(self, patch_table)
    assert(self.v_cache[cur_pos]==nil)
    self.v_cache[cur_pos] = v
    return type, v
end


------------------ index ------------------
local function index_get_value(meta_value, reader, patch_table)
    local tv = type(meta_value)
    if tv == "number" then  -- offset 
        local v = read_offset_value(reader, meta_value, patch_table)
        return v
    else
        return meta_value
    end
end

local function index_meta_index(raw, key)
    if key == nil then
        return nil
    end
    local mt = getmetatable(raw)
    local meta_info  = mt.__meta_info
    local meta_value = meta_info[key]
    local patch_table = mt.__patch_table
    local pv = nil
    if patch_table then
        pv = patch_table[key]
        if pv=="__NIL_VALUE__" then
            return nil
        elseif meta_value=="__NEW_VALUE__" or pv~=nil and type(pv)~="table" then
            return pv
        end
    end
    local v = index_get_value(meta_value, mt.__reader, pv)
    rawset(raw, key, v)
    return v
end

local function index_meta_len(raw)
    local mt = getmetatable(raw)
    local meta_info = mt.__meta_info
    return #meta_info
end

local function __meta_next(raw, key)
    local mt = getmetatable(raw)
    local meta_info = mt.__meta_info
    local k, v = next(meta_info, key)
    local raw_v = rawget(raw, k)
    if raw_v==nil and k then
        v = raw[k]
        rawset(raw, k, v)
    else
        v = raw_v
    end
    return k, v
end


local function index_meta_pairs(raw)
    return __meta_next, raw
end

index_new = function (meta_info, reader, patch_table)
    local raw = {}
    local mt  = {
        __reader = reader,
        __meta_info = meta_info,
        __patch_table = patch_table,
        __index = index_meta_index,
        __len = index_meta_len,
        __pairs = index_meta_pairs,
    }
    return setmetatable(raw, mt)
end


local function decode_binary_data(file_handle, patch_table)
    local reader = reader_new(file_handle)
    local type, v = reader:read_value(patch_table)
    if type ~= wire_type.MAP_WIRE_TYPE and type ~= wire_type.LIST_WIRE_TYPE then
        error("invalid binary data head, must map or list type")
    end
    return v
end

return decode_binary_data

