# lazy_table
a lazy load table from binary data libary. the real value will only load when used. you can use it as a simply database libary. ;)

### encode
serialize table object to binary data file.
~~~.lua
local encode = require "lazy_table.encode"
local source = {
    foo = 11,
    bar = 22,
    int = {
        33, 44, "test_string",
    },
    optional = true,
    [1] = {},
}

local data = encode(source)
write_file("source.lzt", data)
~~~

### decode
create lazy_table object from binary data file.
~~~.lua
local decode = require "lazy_table.decode"
local source_obj = decode("source.lzt")
print(source_obj.int[3])
-- output
-- test_string
~~~

