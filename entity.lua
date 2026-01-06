core.register_entity('stubes:item_visual', {
    initial_properties = {
        physical = false,
        textures = { '' },
        static_save = false,

        pointable = false,
        visual = 'item',
        visual_size = { x = stube.tube_size - 0.001, y = stube.tube_size - 0.001 }, -- prevent z-fighting
        glow = 1,
    },
    on_activate = function(self, staticdata)
        local stack = ItemStack(staticdata)
        self.object:set_properties {
            textures = { stack:get_name() },
        }
    end,
})

local function create_visual(pos, stack)
    return core.add_entity(pos, 'stubes:item_visual', stack:to_string())
end

--- Updates the position visual of an item, if present
---@param item stube.TubedItem
---@param pos vector
---@param dir integer
---@return nil
function stube.update_item_visual(item, pos, dir)
    if not item.entity then return end
    item.entity:move_to(stube.get_precise_connection_pos(pos, dir), true)
end

--- Creates a visual of an item
---@param item stube.TubedItem
---@param pos vector
---@param dir integer
---@return nil
function stube.create_item_visual(item, pos, dir)
    if item.entity then return end
    item.entity = create_visual(stube.get_precise_connection_pos(pos, dir), item.stack)
end

--- Deletes the visual of an item, if there is one
---@param item stube.TubedItem
---@return nil
function stube.delete_item_visual(item)
    if not item.entity then return end
    item.entity:remove()
    item.entity = nil
end

--- PERF: The function name is so long to make you not want to use it often
---
---@param item stube.TubedItem
---@param pos vector
---@param dir integer
function stube.update_or_create_item_visual(item, pos, dir)
    if not item.entity then
        if stube.should_have_visuals(pos) then
            stube.create_item_visual(item, pos, dir)
        else
            return
        end
    end
    item.entity:move_to(stube.get_precise_connection_pos(pos, dir), true)
end

local function get_player_positions()
    local ret = {}
    for _, player in pairs(core.get_connected_players()) do
        ret[#ret + 1] = player:get_pos()
    end
    return ret
end

--- Adds/removes tubestate visuals depending on if they are actually needed
--- PERF: Time complexity: O(amount_of_tubes*amount_of_players) i think, not great, **but its potential to cause lag has yet to be verified**
--- Optionally supply player_positions when you are calling this more than two times.
---
---@param pos vector
---@param player_positions vector[]?
---@return boolean
function stube.should_have_visuals(pos, player_positions)
    if stube.enable_entities == false then return false end

    if not player_positions then player_positions = get_player_positions() end

    for i = 1, #player_positions do
        local player_position = player_positions[i]
        if vector.distance(pos, player_position) <= stube.entity_radius then return true end
    end
    return false
end

local timer = 0
local timer_max = stube.entity_creation_globalstep_time

--- JIT FRIENDLY: Put `iterate_items` stuff in here instead of in the globalstep
--- As FNEW is NYI in luajit; (FNEW = bytecode instruction that is responsible for creating new functions, NYI = not yet implemented)
--- Translation to english: code creating new functions can't be JIT compiled, so will be a LOT slower (like 10x to 50x or something)

local visual_pos
local iterate_create_visuals = function(item, dir)
    stube.create_item_visual(item, visual_pos, dir)
end

local iterate_remove_visuals = function(item, _)
    stube.delete_item_visual(item)
end

-- stube.update updates visuals, this is responsible for adding/deleting them
function stube.visual_globalstep(dtime)
    timer = timer + dtime
    if timer < timer_max then return end
    timer = 0

    local player_positions = get_player_positions()

    -- tubes
    for _, tubes_array in pairs(stube.all_stubes) do
        for hpos, tube_state in pairs(tubes_array) do
            local pos = core.get_position_from_hash(hpos)
            if stube.should_have_visuals(pos, player_positions) then
                for dir, item in pairs(tube_state.connections) do
                    stube.create_item_visual(item, pos, dir)
                end
            else
                for _, item in pairs(tube_state.connections) do
                    stube.delete_item_visual(item)
                end
            end
        end
    end

    -- routing devices
    for routing_type, routing_state_array in pairs(stube.routing_states) do
        local def = stube.registered_routing_node[routing_type]
        for hpos, routing_state in pairs(routing_state_array) do
            local pos = core.get_position_from_hash(hpos)
            if stube.should_have_visuals(pos, player_positions) then
                visual_pos = pos
                def.iterate_items(routing_state, iterate_create_visuals)
            else
                def.iterate_items(routing_state, iterate_remove_visuals)
            end
        end
    end
end

core.register_globalstep(stube.visual_globalstep)
