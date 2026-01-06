--- Aproach:
--- 1) Item tries to go to the target direction (junction algo)
--- 2) Once there, try seeing if it can insert to it
---     - If yes, great
---     - If not, pick another direction
---     - If all directions not, just stay there
--- So yeah, this is just a junction with extra steps, yes

local function junction_move_to_center(state, dir, target_dir, item, pos)
    if state.items[6] == nil then state.items[6] = {} end
    if state.items[6][target_dir] then return end -- occupied
    state.items[dir][target_dir] = nil
    state.items[6][target_dir] = item
    stube.update_item_visual(item, pos, 6)
end

local function junction_move_away_from_center(state, target_dir, item, pos)
    if state.items[target_dir] == nil then state.items[target_dir] = {} end
    if state.items[target_dir][target_dir] then return end -- an item is blocking the way
    state.items[6][target_dir] = nil
    state.items[target_dir][target_dir] = item
    stube.update_item_visual(item, pos, target_dir)
end

local function gate_try_output(state, item, pos, out_pos, out_node, dir, possible_outputs)
    local detach = stube.send_item(item, pos, out_pos, out_node, stube.opposite_wallmounted(dir))
    if detach then
        state.items[dir][dir] = nil
        return
    end

    for other_dir, other_node in pairs(possible_outputs) do
        if other_dir ~= dir then
            detach = stube.send_item(
                item,
                pos,
                vector.add(pos, core.wallmounted_to_dir(other_dir)),
                other_node,
                stube.opposite_wallmounted(other_dir)
            )

            if detach then
                state.items[dir][dir] = nil
                return
            end
        end
    end
end

local gate_size = 0.5 - 0.0001
stube.register_routing_node('stubes:overflow_gate', {
    description = 'Overflow Gate',
    groups = { stube_routing_node = 1, not_in_creative_inventory = stube.experimental and 1 or 0 },

    -- visuals:
    tiles = { { name = 'stube_junction.png', backface_culling = false } },
    use_texture_alpha = 'clip',
    drawtype = 'nodebox',
    sunlight_propagates = true,
    node_box = {
        type = 'fixed',
        fixed = { -gate_size, -gate_size, -gate_size, gate_size, gate_size, gate_size }, -- avoid z fighting, this is an "easter egg" if you manage to notice it
    },
    paramtype2 = 'color',
    paramtype = 'light',
}, {
    speed = stube.default_routing_node_speed,
    accept = function(state, tubed_item, pos, accept_dir)
        state = state ---@type stube.JunctionState

        local target_dir = stube.opposite_wallmounted(accept_dir)

        local accept_side = state.items[accept_dir]
        if not accept_side then
            state.items[accept_dir] = {}
            accept_side = state.items[accept_dir]
        end

        -- okay excellent, so we can just accept

        ---@diagnostic disable-next-line: need-check-nil
        if accept_side[target_dir] then return false end -- if its occupied
        accept_side[target_dir] = tubed_item

        stube.update_item_visual(tubed_item, pos, accept_dir)
        return true
    end,
    iterate_items = function(state, f)
        state = state ---@type stube.JunctionState
        for dir, side in pairs(state.items) do
            for _, item in pairs(side) do
                f(item, dir)
            end
        end
    end,
    update = function(state, hpos)
        state = state ---@type stube.JunctionState
        local pos = core.get_position_from_hash(hpos)

        local possible_outputs = {}
        for i = 0, 5 do
            local dir = core.wallmounted_to_dir(i)
            local neighbor_pos = vector.add(pos, dir)
            local node = stube.get_or_load_node(neighbor_pos)
            if stube.can_connect_to_receiver(node, i, false) == true then possible_outputs[i] = node end
        end

        -- output
        for dir, items in pairs(state.items) do
            for target_dir, item in pairs(items) do
                if dir == target_dir then -- Arrived at destination, no need for any more internal transport, get out of the junction
                    local out_pos = vector.add(stube.tube_state_connection_to_dir(dir), pos)
                    local out_node = stube.get_or_load_node(out_pos)
                    -- try outputting
                    gate_try_output(state, item, pos, out_pos, out_node, dir, possible_outputs)
                end
            end
        end

        -- internal transport

        -- move everything possible away from the center
        local center_items = state.items[6]
        if center_items then
            for target_dir, item in pairs(center_items) do
                junction_move_away_from_center(state, target_dir, item, pos)
            end
        end

        -- move everything possible to the center
        for dir, items in pairs(state.items) do
            for target_dir, item in pairs(items) do
                if dir ~= target_dir then junction_move_to_center(state, dir, target_dir, item, pos) end
            end
        end
    end,
})
