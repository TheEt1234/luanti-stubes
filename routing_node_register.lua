-- Group: `stube_routing_node`=1
-- Transport is handled in stube_transport.lua
-- Routing blocks also keep their entities, they can be transparent

--- You must not add any new non-optional parameters
--- i mean thats not part of the license, its just, i'd rather you not, or it will be a real pain in the butt to update?
---@class stube.RoutingState: table
---@field items table Routing nodes can store tubes hovewer they like
---@field updated_at number Not really used, as routing blocks can't update outside of their trigger
---@field to_remove? boolean

---@class stube.RoutingNodeDef
---@field update fun(state:stube.RoutingState, hpos: number):nil
---@field accept fun(state:stube.RoutingState, item:stube.TubedItem, pos: vector, dir: integer):boolean Returns if the thing that held the item should detach it (so, for example: if ?.accept(...) then tube_state[dir]=nil end)
---@field iterate_items fun(state:stube.RoutingState, f:fun(item:stube.TubedItem, dir:integer?):nil) Used when deleting all items or something
---@field speed number Delay between updates, but routing nodes always update after tubes

---@type { [string]: stube.RoutingNodeDef }
stube.registered_routing_node = {}

---@type table<string, table<integer, stube.RoutingState>>
stube.routing_states = {}

---FIXME: Also remove routing states if they are empty, thats important yknwoww
--- FIXME: add pipeworks tubedevice support
---
---@param routing_def stube.RoutingNodeDef
---@param def core.NodeDef
function stube.register_routing_node(name, def, routing_def)
    stube.registered_routing_node[name] = routing_def
    stube.edit_node_def(name, def)
    core.register_node(name, def)
end

-- UTILS

local IG = core.get_item_group

---@param dir integer
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

--- bad = its empty or state.to_remove == true or type~=node.name
function stube.remove_bad_routing_states(type, state, hpos, node)
    local empty = true
    local def = stube.registered_routing_node[type]
    local pos = core.get_position_from_hash(hpos)

    def.iterate_items(state, function()
        empty = false
    end)

    if empty then state.to_remove = true end
    if node.name ~= type then state.to_remove = true end
    if state.to_remove then
        stube.routing_states[type][hpos] = nil
        def.iterate_items(state, function(item, dir)
            local item_pos = pos
            if dir then item_pos = stube.get_precise_connection_pos(pos, dir) end
            core.add_item(item_pos, item.stack)
        end)
    end
end

local timers = {}
core.register_on_mods_loaded(function()
    for name, def in pairs(stube.registered_routing_node) do
        timers[name] = { current = 0, max = def.speed }
        stube.routing_states[name] = {}
    end
end)

local function process_routing_type(type)
    for hpos, state in pairs(stube.routing_states[type]) do
        local node = stube.get_or_load_node(core.get_position_from_hash(hpos))
        if node.name ~= type then
            state.to_remove = true
        else
            stube.registered_routing_node[node.name].update(state, hpos)
        end
        stube.remove_bad_routing_states(type, state, hpos, node)
    end
end

--- Called by stube.globalstep
function stube.routing_globalstep(dtime)
    for name, timer in pairs(timers) do
        timer.current = timer.current + dtime
        if timer.current >= timer.max then
            process_routing_type(name)
            timer.current = 0
        end
    end
end
