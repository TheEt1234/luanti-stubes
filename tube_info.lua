--- THE TUBE INFO
-- This file is mostly about tube names
-- A tube name is (in lua syntax) `modname .. ':' .. tube_prefix .. '_' .. dir .. xc .. yc .. zc .. nxc .. nyc .. nzc`
-- xc means "is the side +X connected?", yc means "is the side +Y connected?" and so on
-- nxc means "is the side -X connected?" (n means negative, so negative xc => nxc)
--
-- xc, yc, zc, nxc, nyc, nzc are all 1 or 0
--
-- the `dir` specifies the direction of the tube in wallmounted
--
-- To save node count, not all possible configurations of those are valid tubes
-- If the `dir` is pointing to a connection that does not exist, that tube won't exist
--
-- **There is a better approach that could be done**

--    name = name .. '_' .. dir .. xc .. yc .. zc .. nxc .. nyc .. nzc
--    so last 7 characters
function stube.get_tube_name_info(name)
    local ret = {}
    local start = #name - 7
    for i = 1, 7 do
        ret[i] = tonumber(string.sub(name, start + i, start + i))
    end
    return ret
end

local is_short_tube_memo = {}

function stube.is_short_tube(name)
    if is_short_tube_memo[name] ~= nil then return is_short_tube_memo[name] end

    local info = stube.get_tube_name_info(name)
    local amount_of_connections = 0
    for i = 2, 7 do -- info[1] is direction
        if info[i] == 1 then amount_of_connections = amount_of_connections + 1 end
    end

    local straight_tube_index = (stube.wallmounted_to_connections_index[info[1]] + 3) % 6 -- the index opposite to the dir, if that makes sense
    if straight_tube_index == 0 then straight_tube_index = 6 end

    is_short_tube_memo[name] = amount_of_connections == 1 and info[1 + straight_tube_index] == 1
    return is_short_tube_memo[name]
end

function stube.get_prefix_tube_name(name)
    return name:sub(1, -9)
end

function stube.get_tube_dir(name)
    return assert(tonumber(name:sub(-7, -7)), '!? report this as a bug')
end

function stube.split_tube_name(name)
    local ret = {}

    ret.prefix = stube.get_prefix_tube_name(name)
    ret.connections = stube.get_tube_name_info(name)
    ret.dir = table.remove(ret.connections, 1)

    return ret
end

function stube.join_tube_name(split)
    return split.prefix .. '_' .. split.dir .. table.concat(split.connections, '')
end
