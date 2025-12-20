--- Motivation: Tube placement can be very confusing sometimes, and you will never really be sure how a tube is going to get placed
--- Preview is not entirely accurate because it would be difficult to run stube.update_tube

-- 1) entity
core.register_entity('stubes:tube_placement_preview', {
    initial_properties = {
        physical = false,
        pointable = false,
        visual = 'node',
        glow = 14,
        static_save = false,
        show_on_minimap = false,
        visual_size = { x = 0.999, y = 0.999 },
    },
    on_activate = function(self, staticdata, dtime_s)
        local node = core.deserialize(staticdata)
        ---@diagnostic disable-next-line: assign-type-mismatch
        self.object:set_properties { node = node }
    end,
})

--- they all get deleted the next time a new preview is requested
local preview_entities = {}

local is_air = function(node)
    local reg = (core.registered_nodes[node.name] or {})
    return node.name ~= 'air' and reg.air_equivalent ~= 1 and reg.drawtype ~= 'airlike'
end

local timer, delay = 0, 0.1
function stube.tube_preview_globalstep(dtime)
    timer = timer + dtime
    if timer < delay then return end
    timer = 0

    for k, v in ipairs(preview_entities) do
        if type(v) == 'userdata' or type(v) == 'table' and v.remove then v:remove() end -- could be an error idk
        preview_entities[k] = nil
    end

    for _, player in ipairs(core.get_connected_players()) do
        local wielded_item = player:get_wielded_item()
        if core.get_item_group(wielded_item:get_name(), 'stube') == 1 then
            local target_pos, target_pointed, target_node = stube.get_player_pointing(player, is_air)

            if target_pos and target_pointed and target_node and is_air(target_node) then
                target_pos = target_pointed.above
                local face = vector.subtract(target_pointed.above, target_pointed.under)
                local dir = core.dir_to_wallmounted(face)
                local sneaking = player:get_player_control().sneak

                preview_entities[#preview_entities + 1] = core.add_entity(
                    target_pos,
                    'stubes:tube_placement_preview',
                    core.serialize(
                        stube.get_placed_tube_node(
                            wielded_item:get_name(),
                            target_pos,
                            dir,
                            target_pointed,
                            sneaking,
                            true
                        )
                    )
                )

                local other_nodes = stube.get_connect_tubes_to(target_pos, dir, target_pointed, sneaking)
                for k, v in pairs(other_nodes) do
                    table.insert(
                        preview_entities,
                        core.add_entity(v[1], 'stubes:tube_placement_preview', core.serialize(v[2]))
                    )
                end
            end
        end
    end
end
core.register_globalstep(stube.tube_preview_globalstep)
