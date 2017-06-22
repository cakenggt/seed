seed.registered_plants = {}

-- how often node timers for plants will tick, +/- some random value
local function tick(pos)
	minetest.get_node_timer(pos):start(math.random(166, 286))
end
-- how often a growth failure tick is retried (e.g. too dark)
local function tick_again(pos)
	minetest.get_node_timer(pos):start(math.random(40, 80))
end

-- Seed placement
seed.place_seed = function(itemstack, placer, pointed_thing, plantname)
	local pt = pointed_thing
	-- check if pointing at a node
	if not pt then
		return itemstack
	end
	if pt.type ~= "node" then
		return itemstack
	end

	local under = minetest.get_node(pt.under)
	local above = minetest.get_node(pt.above)

	if minetest.is_protected(pt.under, placer:get_player_name()) then
		minetest.record_protection_violation(pt.under, placer:get_player_name())
		return
	end
	if minetest.is_protected(pt.above, placer:get_player_name()) then
		minetest.record_protection_violation(pt.above, placer:get_player_name())
		return
	end

	-- return if any of the nodes is not registered
	if not minetest.registered_nodes[under.name] then
		return itemstack
	end
	if not minetest.registered_nodes[above.name] then
		return itemstack
	end

	-- check if pointing at the top of the node
	if pt.above.y ~= pt.under.y+1 then
		return itemstack
	end

	-- check if you can replace the node above the pointed node
	if not minetest.registered_nodes[above.name].buildable_to then
		return itemstack
	end

	-- check if pointing at soil
	if minetest.get_item_group(under.name, "soil") < 2 then
		return itemstack
	end

	-- check seed item
	local seed_item = minetest.deserialize(itemstack:get_metadata()).item
	if seed_item == nil or seed_item == "" then
		return itemstack
	end

	-- add the node and remove 1 item from the itemstack
	minetest.add_node(pt.above, {name = plantname, param2 = 1})
	minetest.get_meta(pt.above):set_string("item", seed_item)
	tick(pt.above)
	if not (creative and creative.is_enabled_for
			and creative.is_enabled_for(placer:get_player_name())) then
		itemstack:take_item()
	end
	return itemstack
end

seed.grow_plant = function(pos, elapsed)
	local node = minetest.get_node(pos)
	local name = node.name
	local def = minetest.registered_nodes[name]

	if not def.next_plant then
		-- disable timer for fully grown plant
		return
	end

	-- grow seed
	if minetest.get_item_group(node.name, "seed") and def.fertility then
		local soil_node = minetest.get_node_or_nil({x = pos.x, y = pos.y - 1, z = pos.z})
		if not soil_node then
			tick_again(pos)
			return
		end
		-- omitted is a check for light, we assume seeds can germinate in the dark.
		for _, v in pairs(def.fertility) do
			if minetest.get_item_group(soil_node.name, v) ~= 0 then
				local placenode = {name = def.next_plant}
				if def.place_param2 then
					placenode.param2 = def.place_param2
				end
				minetest.swap_node(pos, placenode)
				if minetest.registered_nodes[def.next_plant].next_plant then
					tick(pos)
					return
				end
			end
		end

		return
	end

	-- check if on wet soil
	local below = minetest.get_node({x = pos.x, y = pos.y - 1, z = pos.z})
	if minetest.get_item_group(below.name, "soil") < 3 then
		tick_again(pos)
		return
	end

	-- check light
	local light = minetest.get_node_light(pos)
	if not light or light < def.minlight or light > def.maxlight then
		tick_again(pos)
		return
	end

	-- grow
	local placenode = {name = def.next_plant}
	if def.place_param2 then
		placenode.param2 = def.place_param2
	end
	minetest.swap_node(pos, placenode)

	-- new timer needed?
	if minetest.registered_nodes[def.next_plant].next_plant then
		tick(pos)
	end
	return
end

-- Register plants
seed.register_plant = function(name, def)
	local mname = name:split(":")[1]
	local pname = name:split(":")[2]

	-- Check def table
	if not def.description then
		def.description = "Seed"
	end
	if not def.inventory_image then
		def.inventory_image = "unknown_item.png"
	end
	if not def.steps then
		return nil
	end
	if not def.minlight then
		def.minlight = 1
	end
	if not def.maxlight then
		def.maxlight = 14
	end
	if not def.fertility then
		def.fertility = {}
	end

	seed.registered_plants[pname] = def

	-- Register seed
	local lbm_nodes = {mname .. ":seed_" .. pname}
	local g = {seed = 1, snappy = 3, attached_node = 1, flammable = 2}
	for k, v in pairs(def.fertility) do
		g[v] = 1
	end
	minetest.register_node(":" .. mname .. ":seed_" .. pname, {
		description = def.description,
		tiles = {def.inventory_image},
		inventory_image = def.inventory_image,
		wield_image = def.inventory_image,
		drawtype = "signlike",
		groups = g,
		paramtype = "light",
		paramtype2 = "wallmounted",
		place_param2 = def.place_param2 or nil, -- this isn't actually used for placement
		walkable = false,
		drop = nil,
		sunlight_propagates = true,
		selection_box = {
			type = "fixed",
			fixed = {-0.5, -0.5, -0.5, 0.5, -5/16, 0.5},
		},
		fertility = def.fertility,
		sounds = default.node_sound_dirt_defaults({
			dig = {name = "", gain = 0},
			dug = {name = "default_grass_footstep", gain = 0.2},
			place = {name = "default_place_node", gain = 0.25},
		}),

		on_place = function(itemstack, placer, pointed_thing)
			local under = pointed_thing.under
			local node = minetest.get_node(under)
			local udef = minetest.registered_nodes[node.name]
			if udef and udef.on_rightclick and
					not (placer and placer:get_player_control().sneak) then
				return udef.on_rightclick(under, node, placer, itemstack,
					pointed_thing) or itemstack
			end

			return seed.place_seed(itemstack, placer, pointed_thing, mname .. ":seed_" .. pname)
		end,
		next_plant = mname .. ":" .. pname .. "_1",
		on_timer = seed.grow_plant,
		minlight = def.minlight,
		maxlight = def.maxlight,
		on_dig = seed.dig_seed
	})

	-- Register harvest
	minetest.register_craftitem(":" .. mname .. ":" .. pname, {
		description = pname:gsub("^%l", string.upper),
		inventory_image = mname .. "_" .. pname .. ".png",
		groups = {flammable = 2},
	})

	-- Register growing steps
	for i = 1, def.steps do
		local nodegroups = {snappy = 3, flammable = 2, plant = 1, not_in_creative_inventory = 1, attached_node = 1}
		nodegroups[pname] = i

		local next_plant = nil

		if i < def.steps then
			next_plant = mname .. ":" .. pname .. "_" .. (i + 1)
			lbm_nodes[#lbm_nodes + 1] = mname .. ":" .. pname .. "_" .. i
		end

		minetest.register_node(":" .. mname .. ":" .. pname .. "_" .. i, {
			drawtype = "plantlike",
			waving = 1,
			tiles = {mname .. "_" .. pname .. "_" .. i .. ".png"},
			paramtype = "light",
			paramtype2 = def.paramtype2 or nil,
			place_param2 = def.place_param2 or nil,
			walkable = false,
			buildable_to = true,
			drop = nil,
			selection_box = {
				type = "fixed",
				fixed = {-0.5, -0.5, -0.5, 0.5, -5/16, 0.5},
			},
			groups = nodegroups,
			sounds = default.node_sound_leaves_defaults(),
			next_plant = next_plant,
			on_timer = seed.grow_plant,
			minlight = def.minlight,
			maxlight = def.maxlight,
			on_dig = seed.dig_plant,
			steps = def.steps
		})
	end

	-- replacement LBM for pre-nodetimer plants
	minetest.register_lbm({
		name = ":" .. mname .. ":start_nodetimer_" .. pname,
		nodenames = lbm_nodes,
		action = function(pos, node)
			tick_again(pos)
		end,
	})

	-- Return
	local r = {
		seed = mname .. ":seed_" .. pname,
		harvest = mname .. ":" .. pname
	}
	return r
end


seed.dig_plant = function(pos, node, player)
	-- check seed item
	local seed_item = minetest.get_meta(pos):get_string("item")
	if seed_item == nil or seed_item == "" then
		minetest.remove_node(pos)
		return
	end
	local def = minetest.registered_nodes[node.name]
	local steps = 8
	if def.steps ~= nil then
		steps = def.steps
	end
	local step = tonumber(node.name:split("_")[2])
	local base_rarity = 8 - (step - 1) * 7 / (steps - 1)
	local item_meta = minetest.serialize({item=seed_item})
	if math.random(base_rarity) == 1 then
		add_to_player_inventory(player, seed_item)
	end
	if math.random(base_rarity*2) == 1 then
		add_to_player_inventory(player, seed_item)
	end
	if math.random(base_rarity) == 1 then
		add_to_player_inventory(player, {name="seed:seed_seed", count=1, metadata=item_meta})
	end
	if math.random(base_rarity*2) == 1 then
		add_to_player_inventory(player, {name="seed:seed_seed", count=1, metadata=item_meta})
	end
	minetest.remove_node(pos)
end

seed.dig_seed = function(pos, node, player)
	-- check seed item
	local seed_item = minetest.get_meta(pos):get_string("item")
	if seed_item == nil or seed_item == "" then
		minetest.remove_node(pos)
		return
	end
	local item_meta = minetest.serialize({item=seed_item})
	add_to_player_inventory(player, {name="seed:seed_seed", count=1, metadata=item_meta})
	minetest.remove_node(pos)
end

function add_to_player_inventory(player, itemstack)
	local player_inv = player:get_inventory()
	local dropped = player_inv:add_item("main", itemstack)
	minetest.add_item(player:getpos(), dropped)
end
