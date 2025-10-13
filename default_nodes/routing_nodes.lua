--- Game design: There should be a reason to not use the fastest tube all the time
--- So i am going to passionately give you that reason: Some routing blocks are too slow for them
---
--- Oh btw, the routing blocks will have the speed of a fast tube, because if you want to replace slow tubes with just routing blocks, sure go ahead! that's a creative solution to a fun problem!

--- FIXME: Peacefully remove routing state when dug

local speed = 1 / 3

---@class stube.JunctionState: stube.RoutingState
---@field items table<integer, table<integer, stube.TubedItem?>?> # items[dir][target_dir]

local function move_entity(ent, pos, dir)
    ent:move_to(stube.get_precise_connection_pos(pos, dir), true)
end

local function junction_try_output(state, pos, out_pos, out_node, item, dir)
    local detach = stube.send_item(item, pos, out_pos, out_node, dir)
    if detach then state.items[dir][dir] = nil end
end

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

-- can hold 6*2 + 6 items... that's a lot compared to just 7 items, kinda like a mini chest
-- though i wouldn't use it for that xD

local junction_size = 0.5 - 0.0001
stube.register_routing_node('stubes:junction', {
    description = 'Tube Junction',
    groups = { stube_routing_node = 1 },

    -- visuals:
    tiles = { { name = 'stube_junction.png', backface_culling = false } },
    use_texture_alpha = 'clip',
    drawtype = 'nodebox',
    sunlight_propagates = true,
    node_box = {
        type = 'fixed',
        fixed = { -junction_size, -junction_size, -junction_size, junction_size, junction_size, junction_size }, -- avoid z fighting
    },
    paramtype2 = 'color',
    paramtype = 'light',
}, {
    speed = speed,
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

        -- output
        for dir, items in pairs(state.items) do
            for target_dir, item in pairs(items) do
                if dir == target_dir then -- Arrived at destination, no need for any more internal transport
                    local out_pos = vector.add(stube.tube_state_connection_to_dir(dir), pos)
                    local out_node = stube.get_or_load_node(out_pos)
                    junction_try_output(state, pos, out_pos, out_node, item, dir)
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
