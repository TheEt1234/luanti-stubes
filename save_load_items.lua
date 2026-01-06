-- What's the best way to save a lot of items (potentially up to 10 000, so guessing like 70kb of information)
-- idk haha
-- how does pipeworks solve this unique problem i wonder
-- it makes a file in the world named "luaentities" that uses core.serialize... oh...
-- oh.... that looks inefficient
--
-- and it only writes entities on shutdown
-- which i think would cause a dupe bug if you managed to make luanti segfault, but then maybe you have bigger issues
--
-- maybe i dont need my saving to be "the best way" or to be "perfect"
--
-- ============================================================================================= --
--
-- Anyway, what needs to be saved:
-- 1) stube.all_stubes (with all tubestate updated_at set to 0, stube.current_update_time could probably easily overflow into unsafe floats easily)
-- 2) stube.routing_states
--
-- And tube states also need to be verified (if there is even a tube of that type at that pos )
--
-- Okay
-- i will use core.serialize/deserialize, i am not writing my own serializer
-- when string buffers become a thing, i will use them (if this project doesn't stop being maintained, which realistically, it WILL STOP)
--
-- Also pretty sure, that due to the limits of LuaJit, i cannot be 100% sure that i can support more than 32 767 (2**16/2-1) item stacks
-- If there are more than that, and it cant read it, then i guess it should just discard it. whatever. you might have bigger problems anyway.

-- These are keys of stube.*
-- Their format is { [type: string] = {[pos: poshash] = tube_state}}
-- Also the order of this table matters, don't change it
local to_manage = {
    'all_stubes',
    'routing_states',
}

local save_file_location = stube.save_file_location
local move_file_if_unreadable = save_file_location .. '.unreadable.old'

---@param f fun(t:table,k:any,v:any):nil
local function foreach_key(t, f, seen)
    seen = seen or {}
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        if type(v) == 'table' then
            foreach_key(v, f, seen)
        else
            f(t, k, v)
        end
    end
end

--- these functions are meant to be ran in foreach_key
local function serialize_userdata(t, k, v)
    if type(v) == 'userdata' then
        if v.to_string then
            t[k] = v:to_string()
        else
            t[k] = nil
        end
    end
end

local function deserialize_userdata(t, k, v)
    if type(v) == 'string' and k == 'stack' then -- HACK:
        local stack = ItemStack(v)
        if stack then t[k] = stack end
    end
end

function stube.save_items()
    if not stube.should_save_items then return end
    local file, errmsg = io.open(save_file_location, 'w+b')
    if not file then
        core.log('error', ('Could not save stube items: %s'):format(errmsg))
        return
    end

    local to_save = {}
    for i = 1, #to_manage do
        to_save[i] = table.copy(stube[to_manage[i]])
    end

    -- now... to get rid of the userdata (ItemStacks)
    -- a HACK: must be introduced
    foreach_key(to_save, serialize_userdata)

    local serialized = core.serialize(to_save)
    file:write(serialized)
    file:close()
end

local function insert_all(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
    return t1
end

-- call only at before mod-load time please
function stube.load_items()
    local file, errmsg = io.open(save_file_location, 'rb')
    local contents = file and file:read '*a'
    if file then file:close() end
    if not stube.should_save_items and contents then
        os.remove(save_file_location) -- Remove so it doesn't get accidentally restored, causing an item duplication glitch
        return
    elseif not stube.should_save_items then
        return
    elseif not contents then
        local file = io.open(save_file_location, 'w+')
        if file then
            file:write ''
            file:close()
        end
        return
    end

    if contents == '' then return end

    local loaded, errmsg = core.deserialize(contents, true)

    if errmsg then
        core.log('error', 'Could not load stube item data: ' .. errmsg)
        os.rename(save_file_location, move_file_if_unreadable)
        return
    end

    for i = 1, #to_manage do
        ---@diagnostic disable: need-check-nil
        insert_all(stube[to_manage[i]], loaded[i])
        foreach_key(stube[to_manage[i]], deserialize_userdata)
        core.after(0, function()
            for type, positions in pairs(stube[to_manage[i]]) do
                for hpos, tube_state in pairs(positions) do
                    local pos = core.get_position_from_hash(hpos)
                    if not stube.get_or_load_node(pos).name:find(type, 1, true) then
                        positions[hpos] = nil
                        error('CHECK FAILED:' .. dump(stube.get_or_load_node(pos)))
                    else
                        tube_state.updated_at = 0
                    end
                end
            end
        end)
    end
end

stube.load_items()
core.register_on_shutdown(stube.save_items)
