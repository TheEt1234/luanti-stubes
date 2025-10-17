--- Configuration in init.lua
---@class stube
stube = {
    -- The debug mode for STubes
    -- Currently, it just pollutes the creative inventory with tube variants
    debug = false,

    -- This is mostly an option for testing, there is no actual reason to disable them (You can just set entity_radius to something low if you don't like them)
    enable_entities = true,

    -- Item Entities will be shown when the player is this many nodes near to them
    -- Set to a huge value to almost always have item entities (Why would you do that?)
    -- This feature has been shown to help, as it skips laggy entity move_to calls
    entity_radius = 16,

    -- The globalstep for creating/removing entities will be run every <that value> seconds
    entity_creation_globalstep_time = 1,

    -- Sets the size of the tubes. Each tube must be the same size.
    tube_size = 3 / 16,

    --- The amount of time it takes to update stube's default routing nodes in seconds
    --- The number chosen (1/3) was partly because of game design
    default_routing_node_speed = 1 / 3,
}

--- This function is guaranteed to get a node
--- ------------------------------------------
---
--- Creating a utils file just for this is silly, so i am putting it here
--- BTW: This is a trick from the mt-mods/technic luanti mod
---@param pos ivec
---@return core.Node.get
stube.get_or_load_node = function(pos)
    local get_or_load_node_node = core.get_node_or_nil(pos)
    if get_or_load_node_node then return get_or_load_node_node end
    core.load_area(pos)
    return core.get_node(pos)
end

local mp = core.get_modpath(core.get_current_modname())

--- Library:
dofile(mp .. '/entity.lua')

dofile(mp .. '/tube_info.lua')
dofile(mp .. '/receiver_types.lua')
dofile(mp .. '/tube_placement.lua')
dofile(mp .. '/tube_register.lua')
dofile(mp .. '/tube_transport.lua')
dofile(mp .. '/tube_hud.lua')

dofile(mp .. '/routing_node_register.lua')

--- Default nodes:

local default_nodes_path = mp .. '/default_nodes'
dofile(default_nodes_path .. '/tubes.lua')
dofile(default_nodes_path .. '/junction.lua')
dofile(default_nodes_path .. '/overflow_gates.lua')
