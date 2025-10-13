-- Items are transferred 1 item/update... unless you change it i guess

local h, uh = core.hash_node_position, core.get_position_from_hash

---@class stube.TubedItem: table
---@field stack core.ItemStack
---@field owner? string
---@field entity? core.EntityRef

--- The state of any active tube
--- The node underneeth a tube state can be anything, and it can change at any time
--- Therefore it is wise not to store things like direction
---@class stube.TubeState
---@field connections table<integer, stube.TubedItem?> items[wallmounted_dir]=item, items[6] = item at the center
---@field updated_at integer
---@field to_remove? boolean

---@type table<string, table<number, stube.TubeState>>
local stubes = {} -- A table of all the tubed items, t[tube_name][h(tube_pos)] = TubeState
stube.all_stubes = stubes
stube.current_update_time = 0 -- used in tubed items

local timers = {}
core.register_on_mods_loaded(function()
    for name, def in pairs(stube.registered_tubes) do
        timers[name] = { current = 0, max = def.speed }
        stubes[name] = {}
    end
end)

---@param dir number|nil
local function move_entity(ent, pos, dir)
    ent:move_to(stube.get_precise_connection_pos(pos, dir), true)
end

local function move_connection(tube_state, dir1, dir2, pos)
    if dir1 ~= dir2 then -- if it is equal, you are just moving the entity
        assert(
            not tube_state.connections[dir2],
            '[stubes]Tried overriding with `local function move_connection(...)` in stubes/transport.lua, report this is a bug'
        )
        tube_state.connections[dir2] = tube_state.connections[dir1]
        tube_state.connections[dir1] = nil
    end

    local ent = tube_state.connections[dir2].entity
    if ent then move_entity(ent, pos, dir2) end
end

local function delete_connection(tube_state, dir)
    local ent = tube_state.connections[dir].entity
    tube_state.connections[dir] = nil
    if ent then ent:remove() end
end

local IG = core.get_item_group

-- Every item gets pushed to the center (in a set order, even if random order makes more sense), center gets pushed to tube dir, tube dir item get transported
---@param tube_state stube.TubeState
local function inter_tube_transport(tube_state, tube_dir, tube_vpos, is_short, already_transported_to_center)
    local connections = tube_state.connections
    if connections[6] == nil then
        for i = 0, 5 do
            if i ~= tube_dir and connections[i] ~= nil then -- one non-empty item from all directions except tube dir gets put into the center
                move_connection(tube_state, i, 6, tube_vpos)
                break
            end
        end
    elseif connections[tube_dir] == nil and connections[6] ~= nil and not already_transported_to_center then -- if center is empty, the item from the center will come to replace it..
        -- actually don't do this if it is a short tube
        if is_short then return end

        move_connection(tube_state, 6, tube_dir, tube_vpos)
        inter_tube_transport(tube_state, tube_dir, tube_vpos, is_short, true) -- May look worrysome to some, but makes sense if you think about it
    end

    -- FIXME: Drop items which are in impossible places
    -- Do that after verifying they can't get there naturally
end

--- 1 item/update
---@param tube_state stube.TubeState
local function push_items_to_next_tube(next_node, next_pos, tube_state, tube_dir, tube_vpos)
    local prefix = stube.get_prefix_tube_name(next_node.name)
    local next_tube_def = stube.registered_tubes[prefix]
    local next_tube_hpos = core.hash_node_position(next_pos)
    local next_tube_state = stubes[prefix][next_tube_hpos]
    local is_empty = next_tube_state == nil
    local can_insert = true
    local next_tube_dir = stube.get_tube_dir(next_node.name)
    local opposite_tube_dir = stube.opposite_wallmounted(tube_dir)

    if is_empty == false then
        can_insert = next_tube_state.connections[opposite_tube_dir] == nil -- If there isn't an item in the way
    end
    can_insert = can_insert and next_tube_dir ~= opposite_tube_dir -- And the tube must not be pointing away from us

    if is_empty then
        stubes[prefix][next_tube_hpos] = {
            connections = {},
            updated_at = stube.current_update_time,
        }
        next_tube_state = stubes[prefix][next_tube_hpos]
    end

    if can_insert then
        local item = tube_state.connections[tube_dir]
        if not item then return true, next_tube_hpos, next_tube_def, stubes[prefix], prefix end -- There is nothing to push, so don't bother with updating next tubes

        next_tube_state.connections[opposite_tube_dir] = item
        tube_state.connections[tube_dir] = nil

        move_connection(next_tube_state, opposite_tube_dir, opposite_tube_dir, next_pos) -- just update entity

        return true, next_tube_hpos, next_tube_def, stubes[prefix], prefix
    else
        return false, next_tube_hpos, next_tube_def, stubes[prefix], prefix
    end
end

---@param tube_state stube.TubeState
function stube.delete_tube_state(tube_state, tubes_array, tube_hpos)
    local tube_vpos = uh(tube_hpos)
    for dir, connection in pairs(tube_state.connections) do
        if connection.entity then connection.entity:remove() end
        local pos = stube.get_precise_connection_pos(tube_vpos, dir)
        core.add_item(pos, connection.stack)
    end
    tubes_array[tube_hpos] = nil
end

---@param tube_state stube.TubeState
local function delete_if_empty_state(tube_hpos, tube_state, tubes_array)
    local empty = true
    for i = 0, 6 do
        if tube_state.connections[i] ~= nil then
            empty = false
            break
        end
    end
    if empty then tube_state.to_remove = true end

    if tube_state.to_remove then stube.delete_tube_state(tube_state, tubes_array, tube_hpos) end
end

--- This is a very recursive function
---@param tube_state stube.TubeState
---@param tube_def stube.TubeDef
---@param tube_hpos integer
---@param prefix string
function stube.update_tube(tube_hpos, tube_def, tube_state, prefix)
    if tube_state.updated_at == stube.current_update_time then return end
    tube_state.updated_at = stube.current_update_time

    local tube_vpos = uh(tube_hpos)

    local this_node = stube.get_or_load_node(tube_vpos)
    if stube.get_prefix_tube_name(this_node.name) ~= prefix then
        tube_state.to_remove = true
        return
    end

    if
        not tube_def.should_update(
            tube_hpos,
            tube_state,
            stube.get_or_load_node(core.get_position_from_hash(tube_hpos))
        )
    then
        return
    end -- In cases like short tubes you don't want to update the tube, as there is nowhere that items can go, there basically wouldn't be a next node

    local tube_dir = stube.get_tube_dir(this_node.name)

    local next_pos, next_node = tube_def.get_next_pos_and_node(tube_hpos, tube_state, tube_dir)

    local sending_side = tube_state.connections[tube_dir]
    if not sending_side then
        inter_tube_transport(tube_state, tube_dir, tube_vpos, stube.is_short_tube(this_node.name))
        return
    end

    if IG(next_node.name, 'stube') == 1 then -- Worst case: another tube, oh no xD
        local success, next_tube_hpos, next_tube_def, next_tube_type_array, next_tube_prefix =
            push_items_to_next_tube(next_node, next_pos, tube_state, tube_dir, tube_vpos)
        if success == true then -- HACK: HACK: I don't know how this works but it does
            -- So sometimes tubes were randomly going faster than they should??? and this fixed that?
            next_tube_type_array[next_tube_hpos].updated_at = stube.current_update_time
        end

        if success == false then
            ---@diagnostic disable-next-line
            stube.update_tube(next_tube_hpos, next_tube_def, next_tube_type_array[next_tube_hpos], next_tube_prefix)
            push_items_to_next_tube(next_node, next_pos, tube_state, tube_dir, tube_vpos)
            delete_if_empty_state(tube_hpos, tube_state, stubes[prefix])
        end
    elseif stube.is_receiver(next_node) then
        local should_delete =
            stube.send_item(sending_side, tube_vpos, next_pos, next_node, stube.opposite_wallmounted(tube_dir))

        if sending_side.stack == nil or sending_side.stack:is_empty() then should_delete = true end
        if should_delete then tube_state.connections[tube_dir] = nil end
    end

    inter_tube_transport(tube_state, tube_dir, tube_vpos, stube.is_short_tube(this_node.name))
end

function stube.process_tube_type(tube_name, tube_def)
    local tubes = stubes[tube_name]
    for tube_hpos, tube_state in pairs(tubes) do
        stube.update_tube(tube_hpos, tube_def, tube_state, tube_name)
        delete_if_empty_state(tube_hpos, tube_state, tubes)
    end
end

---@param dtime number
---@return nil
function stube.globalstep(dtime)
    stube.current_update_time = stube.current_update_time + 1
    stube.routing_globalstep(dtime)
    for name, timer in pairs(timers) do
        timer.current = timer.current + dtime
        if timer.current >= timer.max then
            stube.process_tube_type(name, stube.registered_tubes[name])
            timer.current = 0
        end
    end
end
core.register_globalstep(stube.globalstep)
