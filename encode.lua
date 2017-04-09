local wire_type = require "wire_type"

local type = type
local assert = assert
local tostring = tostring

local buffer_stream_mt = {}
buffer_stream_mt.__index = buffer_stream_mt


local function buffer_stream_new()
    local raw = {
        v_count = 0,
        v_len = 0,
    }
    return setmetatable(raw, buffer_stream_mt)
end

function buffer_stream_mt:write(s)
    self.v_count = self.v_count + 1
    self[self.v_count] = s
    local cur_pos = self.v_len
    self.v_len = self.v_len + #s
    return cur_pos
end

function buffer_stream_mt:dump()
    local s = table.concat(self, "", 1, self.v_count)
    assert(#s == self.v_len)
    return s
end

function buffer_stream_mt:clear()
    self.v_count = 0
    self.v_len = 0
end


---------------- encode binary data ----------------
local NIL_WIRE_TYPE      = wire_type.NIL_WIRE_TYPE
local MAP_WIRE_TYPE      = wire_type.MAP_WIRE_TYPE
local LIST_WIRE_TYPE     = wire_type.LIST_WIRE_TYPE
local STRING_WIRE_TYPE   = wire_type.STRING_WIRE_TYPE
local REAL_WIRE_TYPE     = wire_type.REAL_WIRE_TYPE
local INTEGET_WIRE_TYPE  = wire_type.INTEGET_WIRE_TYPE
local TRUE_WIRE_TYPE     = wire_type.TRUE_WIRE_TYPE
local FALSE_WIRE_TYPE    = wire_type.FALSE_WIRE_TYPE
local OFFSET_WIRE_TYPE   = wire_type.OFFSET_WIRE_TYPE


local function check_table_is_list(t)
    local k = next(t)
    if k ~= 1 then
        return false
    else
        k = next(t, #t)
        return k == nil and true or false
    end
end


local function stripping_all_value(t, out_map, filter_map)
    filter_map = filter_map or {}
    if filter_map[t] then
        return
    else
        filter_map[t] = true
    end

    local is_map = not check_table_is_list(t)
    for k,v in pairs(t) do
        local tv = type(v)
        if is_map then
            local tk = type(k)
            if tk == "string" or tk == "number" then
                out_map[k] = true
            elseif tk ~= "boolean" then
                error("invalid stripping key type: "..tk)
            end
        end

        if tv == "string" or tv == "number" then
            out_map[v] = true
        elseif tv == "table" then
            stripping_all_value(v, out_map, filter_map)
        elseif tv ~= "boolean"  then
            error("invalid stripping value type: "..tv)
        end
    end
end



local encode_drive_map = nil

local function encode_index_key_and_value(v, all_data_pos_map)
    local tv = type(v)
    if tv=="boolean" then
        return encode_drive_map.boolean(v)
    else
        assert(v)
        local pos = all_data_pos_map[v]
        assert(pos)
        local s = encode_drive_map.offset(pos)
        return s
    end
end

encode_drive_map = {
    string = function (v)
        assert(#v <= 0xffff, "string is too long")
        return string.pack("<I1s2", STRING_WIRE_TYPE, v)
    end,

    boolean = function (v)
        return string.pack("<I1", v and TRUE_WIRE_TYPE or FALSE_WIRE_TYPE)
    end,

    number = function (v)
        if v//1==v then
            return string.pack("<I1i8", INTEGET_WIRE_TYPE, v)
        else
            return string.pack("<I1d", REAL_WIRE_TYPE, v)
        end
    end,

    offset = function (v)
        assert(v>=0 and v<=0xffffffff)
        return string.pack("<I1I4", OFFSET_WIRE_TYPE, v)
    end,

    ["nil"] = function ()
        return string.pack("<I1", NIL_WIRE_TYPE)
    end,

    list = function (info, all_data_pos_map)
        local stream = buffer_stream_new()
        local entry = info.entry
        local entry_len = #entry
        assert(entry_len<=0xffffffff)
        local head = string.pack("<I1I4", LIST_WIRE_TYPE, entry_len)
        stream:write(head)
        for i,v in ipairs(entry) do
            local value = v.value
            if value then
                s = encode_index_key_and_value(value, all_data_pos_map)
            else
                s = encode_drive_map["nil"]()
            end
            stream:write(s)
        end
        return stream:dump()
    end,

    map = function (info, all_data_pos_map)
        local stream = buffer_stream_new()
        local entry = info.entry
        local entry_len = #entry
        assert(entry_len*2<=0xffffffff)
        local head = string.pack("<I1I4", MAP_WIRE_TYPE, entry_len)
        stream:write(head)
        for i,v in ipairs(entry) do
            local ks = encode_index_key_and_value(v.key, all_data_pos_map)
            local vs = encode_index_key_and_value(v.value, all_data_pos_map)
            stream:write(ks)
            stream:write(vs)
        end
        return stream:dump()
    end,
}


local function encode_all_value(t)
    local pos_map = {}
    local out_map = {}
    stripping_all_value(t, out_map)
    local out= {}
    for k,v in pairs(out_map) do
        out[#out+1] = k
    end
    table.sort(out, function (a, b) return tostring(a)<tostring(b) end)

    local all_value_stream = buffer_stream_new()
    for i,v in ipairs(out) do
        local tv = type(v)
        local f = encode_drive_map[tv]
        local s = f(v)
        pos_map[v] = all_value_stream:write(s)
    end

    return all_value_stream:dump(), pos_map
end


local function stripping_all_index(t, path, out, filter_map)
    filter_map = filter_map or {}
    if filter_map[t] then
        return
    else
        filter_map[t] = true
    end

    local is_list = check_table_is_list(t)
    local entry = {}
    out[#out+1] = {
        type = is_list and "list" or "map",
        entry = entry,
        raw_value = t,
        path = table.concat(path, "."),
    }

    local path_len = #path+1
    if is_list then
        for i=1,#t do
            local v = t[i]
            entry[i] = {value = v}
            if type(v) == "table" then
                path[path_len] = tostring(i)
                stripping_all_index(v, path, out, filter_map)
                path[path_len] = nil
            end
        end
    else
        for k,v in pairs(t) do
            entry[#entry+1] = {
                key = k,
                value = v,
            }
            if type(v) == "table" then
                path[path_len] = tostring(k)
                stripping_all_index(v, path, out, filter_map)
                path[path_len] = nil
            end
        end
    end
end


local type_lens = {
    string = 5,
    boolean = 1,
    table = 5,
    number = 5,
    ["nil"] = 1,
}
local function cal_list_len(info)
    assert(info.type == "list")
    local entry = info.entry
    local len = 5
    for i,v in ipairs(entry) do
        local l = type_lens[type(v.value)]
        len = len + l
    end
    return len
end

local function cal_map_len(info)
    assert(info.type == "map")
    local entry = info.entry
    local len = 5
    for i,v in ipairs(entry) do
       local key = v.key
       local lk = type_lens[type(key)]
       local value = v.value
       local lv = type_lens[type(value)]
       len = len + lk + lv
    end
    return len
end


local function encode_all_index(t, value_pos_map)
    local out_list = {}
    stripping_all_index(t, {"/"}, out_list)
    table.sort(out_list, function (a, b)
            return a.path < b.path
        end)

    local pos = 0
    local all_data_pos_map = {}
    for i,info in ipairs(out_list) do
        local type = info.type
        local raw_value = info.raw_value
        info.pos = pos
        assert(all_data_pos_map[raw_value]==nil)
        all_data_pos_map[raw_value] = pos
        setmetatable(raw_value, {__tostring = function () 
            return "{"..info.path.."}" end
            }
        )
        if type=="list" then
            info.len = cal_list_len(info)
        elseif type=="map" then
            info.len = cal_map_len(info)
            local entry = info.entry
            table.sort(entry, function (a, b) 
                return tostring(a.key)<tostring(b.key) end
            )
        else
            error("error type:"..type)
        end
        pos = pos + info.len
    end

    -- merge value value_pos_map
    for k,v in pairs(value_pos_map) do
        assert(all_data_pos_map[k]==nil)
        all_data_pos_map[k] = pos+v
    end

    local stream = buffer_stream_new()
    for i,info in ipairs(out_list) do
        local type = info.type
        local f = encode_drive_map[type]
        local s = f(info, all_data_pos_map)
        stream:write(s)
    end
    return stream:dump(), all_data_pos_map
end



local function encode_binary_data(t)
    local all_data_s, value_pos_map = encode_all_value(t)
    local all_index_s, all_data_pos_map = encode_all_index(t, value_pos_map)
    return all_index_s..all_data_s, all_data_pos_map
end


return encode_binary_data