--- Used for compatibility with different kinds of receivers
--- see stube.register_receiver_type
---@class stube.ReceiverTypeDef
---@field is_receiver fun(node: core.Node.get): boolean
---@field can_connect_to_receiver fun(node: core.Node.get, tube_dir: integer, as_output: boolean): boolean as_output means if the receiver is an output
---@field receive_item fun(item: stube.TubedItem, from_pos: ivec, pos: ivec, node: core.Node.get, dir: integer):boolean Returns if it should delete the item from itself. Otherwise it can change item.stack. If it's nil or empty, it's the callers job to destroy that tubed item.
---@field edit_node_def (fun(name: string, def: table):nil)? Example: Lets say you want to make STubes receive items from pipeworks, you would add relevant functions to the definition (so def.tube = {...}), `name` MAY NOT BE A VALID NODE NAME

stube.registered_receiver_types = {} ---@type stube.ReceiverTypeDef[]

--- Registers a receiver type to stube.registered_receiver_types
---@param def stube.ReceiverTypeDef
function stube.register_receiver_type(def)
    table.insert(stube.registered_receiver_types, def)
end

--- Checks if something is a receiver AND if it can connect to it
---@param node core.Node.get
---@param dir integer
---@param as_output boolean **If receiver is being connected as output.** Some mods have different rules for connection if something is an input vs an output, if that makes sense.
function stube.can_connect_to_receiver(node, dir, as_output)
    for _, def in pairs(stube.registered_receiver_types) do
        if def.can_connect_to_receiver(node, dir, as_output) then return true end
    end
    return false
end

--- Checks if a given node is a receiver, does not check if it can actually insert from a direction (if that makes sense, if not make a GH issue)
---@param node core.Node.get
function stube.is_receiver(node)
    for _, def in pairs(stube.registered_receiver_types) do
        if def.is_receiver(node) then return true end
    end
    return false
end

--- !! Changes item.stack
--- Can change it to nil or empty
--- If this returns true, you should do tube_state[dir]=nil, and not worry about deleting the entity or etc.
---@return boolean detach_item_from_itself
---@nodiscard
---@param item stube.TubedItem
---@param from_pos vector
---@param pos vector
---@param node core.Node.get
---@param dir integer
function stube.send_item(item, from_pos, pos, node, dir)
    for _, def in pairs(stube.registered_receiver_types) do
        if def.is_receiver(node) then return def.receive_item(item, from_pos, pos, node, dir) end
    end
    return false
end

---@param name string May not be a valid node name
---@param def table
function stube.edit_node_def(name, def)
    for _, receiver_def in pairs(stube.registered_receiver_types) do
        if receiver_def.edit_node_def then receiver_def.edit_node_def(name, def) end
    end
end

--====================
--- ACTUAL RECEIVERS
--====================

-- stubes's tubes (not used by tubes, instead by anything else)
stube.register_receiver_type {
    is_receiver = function(node)
        return core.get_item_group(node.name, 'stube') == 1
    end,
    can_connect_to_receiver = function(node, dir) -- not used
        return core.get_item_group(node.name, 'stube') == 1
    end,

    -- Called by anything that **isn't** an stube, as that has special updating behavior
    receive_item = function(item, from_pos, pos, node, dir)
        local name = node.name
        local prefix = stube.get_prefix_tube_name(name)
        local state = stube.all_stubes[prefix][core.hash_node_position(pos)]
        if not state then
            state = {
                connections = {},
                updated_at = stube.current_update_time,
            }
            stube.all_stubes[prefix][core.hash_node_position(pos)] = state
        end

        if state.connections[dir] == nil then
            state.connections[dir] = item
            stube.update_or_create_item_visual(item, pos, dir)
            return true
        end
        return false
    end,
}

-- routing nodes
stube.register_receiver_type {
    is_receiver = function(node)
        return core.get_item_group(node.name, 'stube_routing_node') == 1
    end,
    can_connect_to_receiver = function(node, _)
        return core.get_item_group(node.name, 'stube_routing_node') == 1
    end,
    receive_item = function(item, from_pos, pos, node, dir)
        local def = stube.registered_routing_node[node.name]
        local poshash = core.hash_node_position(pos)

        local state = stube.routing_states[node.name][poshash]
        if not state then
            stube.routing_states[node.name][poshash] = { items = {}, updated_at = 0 }
            state = stube.routing_states[node.name][poshash]
        end

        return def.accept(state, item, pos, dir)
    end,
}

--- PIPEWORKS

-- pipeworks has a better solution im not doing for licensing, so this horrible hack will have to do
-- Suggest a better solution please :D thank you
local function process_pipeworks_connect_sides(connect_sides, node, tube_dir)
    local facedir = node.param2
    local facedir_vector = core.facedir_to_dir(facedir)
    if facedir > 23 then facedir = 0 end
    local rotate_by = -vector.dir_to_rotation(facedir_vector)
    if math.floor(facedir / 4) ~= 0 and rotate_by.y < -1 then rotate_by.x = -(math.pi / 2) end -- HACK, that i am not going to fix, this was derived from brute force, it allows placing tubes to tubedevices from above work, specifically filter injectors
    local correct_dir = vector.rotate(tube_dir, rotate_by)
    local wallmounted_dir = core.dir_to_wallmounted(correct_dir)

    local index = (wallmounted_dir == 0 and 'top')
        or (wallmounted_dir == 1 and 'bottom')
        or (wallmounted_dir == 2 and 'right')
        or (wallmounted_dir == 3 and 'left')
        or (wallmounted_dir == 4 and 'front')
        or (wallmounted_dir == 5 and 'back')
    return connect_sides[index] == 1 or connect_sides[index] == true
end

local function is_tubedevice(nodename)
    local reg = core.registered_nodes[nodename]
    if not reg then return false end
    if reg.tubelike == 1 then return false end -- If it's a pipeworks tube, that's tootally different
    if reg.tube then return true end
    return false
end

local function pipeworks_insert_object(pos, node, stack, vel, owner)
    local insert_dir = core.dir_to_wallmounted(-vector.round(vel))

    local item = {
        stack = stack,
        owner = owner,
    }
    local return_nothing = stube.send_item(item, vector.add(pos, -vector.round(vel)), pos, node, insert_dir)
    if return_nothing then return ItemStack() end
    return stack
end

--- Register pipeworks compatibility
stube.register_receiver_type {
    is_receiver = function(node)
        return is_tubedevice(node.name)
    end,
    can_connect_to_receiver = function(node, dir)
        if not is_tubedevice(node.name) then return false end
        local def = core.registered_nodes[node.name]

        if def.tube.connect_sides then
            return process_pipeworks_connect_sides(def.tube.connect_sides, node, core.wallmounted_to_dir(dir))
        end
        return true
    end,
    receive_item = function(item, from_pos, pos, node, dir)
        local def = core.registered_nodes[node.name]
        if not def.tube.insert_object then return false end -- Examples: The filter injector

        local vel = table.copy(core.wallmounted_to_dir(stube.opposite_wallmounted(dir)))
        vel.speed = 1

        item.stack = def.tube.insert_object(pos, node, item.stack, vel, item.owner)
        if item.stack == nil or item.stack:is_empty() and item.entity then
            item.entity:remove()
            return true
        end
        return false
    end,
    edit_node_def = function(name, def)
        def.groups = def.groups or {}
        def.groups.tubedevice = 1
        def.groups.tubedevice_receiver = 1
        local old_after_place = def.after_place_node
        def.after_place_node = function(...)
            pipeworks.after_place(...)
            return old_after_place(...)
        end

        local old_after_dig = def.oafter_dig_node
        def.after_dig_node = function(...)
            pipeworks.after_dig(...)
            return old_after_dig(...)
        end

        def.tube = {
            insert_object = pipeworks_insert_object,
            can_insert = nil, -- TODO: Not Yet Implemented, does not matter much
            connect_sides = { front = 1, back = 1, left = 1, right = 1, top = 1, bottom = 1 },
        }
    end,
}

--- Pipeworks tubes have a few ways to identify them:
--- groups: tube=1, tubedevice = 1
--- def: def.tubelike = 1, def.tube ~= nil
---
--- i think that's enough ways to maybe identify them
local function is_pipeworks_tube(name)
    local def = core.registered_nodes[name] --[[@as table]]
    if not def then return false end

    if core.get_item_group(name, 'tube') ~= 1 then return false end
    if core.get_item_group(name, 'tubedevice') ~= 1 then return false end
    if not def.tubelike == 1 then return false end
    if not def.tube then return false end
    return true
end

--- Pipeworks tubes
stube.register_receiver_type {
    is_receiver = function(node)
        return is_pipeworks_tube(node.name)
    end,
    can_connect_to_receiver = function(node, dir)
        if not is_pipeworks_tube(node.name) then return false end
        local def = core.registered_nodes[node.name]

        if def.tube.connect_sides then
            return process_pipeworks_connect_sides(def.tube.connect_sides, node, core.wallmounted_to_dir(dir))
        end
        return true
    end,
    receive_item = function(item, from_pos, pos, node, dir)
        --- must check tube.can_go, then pipeworks.tube_inject_item
        local def = core.registered_nodes[node.name]

        local vdir = core.wallmounted_to_dir(stube.opposite_wallmounted(dir))
        local vel = table.copy(vdir)
        vel.speed = 1

        if def.tube.can_go then
            if not def.tube.can_go(pos, node, vel, item.stack, {}) then return false end
        end

        pipeworks.tube_inject_item(pos, from_pos, vel, item.stack, item.owner or '')
        stube.delete_item_visual(item)
        return true
    end,
}
