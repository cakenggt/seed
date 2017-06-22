-- Global seed namespace
seed = {}
seed.path = minetest.get_modpath("seed")

-- Load files
dofile(seed.path .. "/api.lua")

-- blank seed
minetest.register_node("seed:seed_seed_blank", {
	description = "Blank Seed",
	tiles = {"seed_seed_seed_blank.png"},
	inventory_image = "seed_seed_seed_blank_item.png",
	wield_image = "seed_seed_seed_blank_item.png",
	drawtype = "plantlike",
	groups = {seed = 1, snappy = 3, attached_node = 1, flammable = 2},
	paramtype = "light",
	buildable_to = true,
	waving = 1,
	walkable = false,
	sunlight_propagates = true,
	selection_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, -5/16, 0.5},
	},
	sounds = default.node_sound_dirt_defaults({
		dig = {name = "", gain = 0},
		dug = {name = "default_grass_footstep", gain = 0.2},
		place = {name = "default_place_node", gain = 0.25},
	})
})

-- blank seed decoration
minetest.register_decoration({
	deco_type = "simple",
	place_on = {"default:dirt_with_grass", "default:desert_sand"},
	sidelen = 16,
	fill_ratio = 0.003,
	biomes = {"grassland"},
	decoration = "seed:seed_seed_blank",
	height = 1,
})

-- seed
seed.register_plant("seed:seed", {
	description = "Seed",
	inventory_image = "seed_seed_seed.png",
	steps = 8,
	minlight = 13,
	maxlight = default.LIGHT_MAX,
	fertility = {"grassland"},
	groups = {flammable = 4},
})

function validate_seed_craft(old_craft_grid)
	local seed
	local seed_index
	local copy
	local copy_index
	for i = 1, #old_craft_grid do
		if old_craft_grid[i]:get_name() == "seed:seed_seed_blank" then
			if seed ~= nil then
				-- error
				return nil
			end
			seed = old_craft_grid[i]
			seed_index = i
		elseif old_craft_grid[i]:get_name() ~= "" then
			if copy ~= nil then
				-- error
				return nil
			end
			copy = old_craft_grid[i]
			copy_index = i
		end
	end
	if seed ~= nil and copy ~= nil then
		return {
			seed=seed,
			seed_index=seed_index,
			copy=copy,
			copy_index=copy_index
		}
	else
		return nil
	end
end

minetest.register_craft_predict(function(itemstack, player, old_craft_grid, craft_inv)
	if validate_seed_craft(old_craft_grid) ~= nil then
		return ItemStack({name="seed:seed_seed", count=1})
	end
	return nil
end)

minetest.register_on_craft(function(itemstack, player, old_craft_grid, craft_inv)
	local validate_result = validate_seed_craft(old_craft_grid)
	if validate_result ~= nil then
		local copy_name = validate_result.copy:get_name()
		validate_result.copy:take_item()
		validate_result.seed:take_item()
		-- put back any leftover items
		craft_inv:set_stack("craft", validate_result.copy_index, validate_result.copy)
		craft_inv:set_stack("craft", validate_result.seed_index, validate_result.seed)
		return ItemStack({name="seed:seed_seed", count=1, metadata=minetest.serialize({item=copy_name})})
	end
	return nil
end)
