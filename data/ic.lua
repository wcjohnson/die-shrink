local constants = require("lib.constants")

local entity_sprite = {}
for idx, direction in pairs({ "north", "east", "south", "west" }) do
	---@type data.Sprite
	entity_sprite[direction] = {
		filename = __GRAPHICS_PATH__ .. "ic-entity.png",
		width = 128,
		height = 128,
		scale = 0.25,
		x = (idx - 1) * 128,
		shift = util.by_pixel(0, 0),
	}
end

---@type data.SimpleEntityWithOwnerPrototype
local ic = {
	-- PrototypeBase
	type = "simple-entity-with-owner",
	name = constants.ic_name,

	-- SimpleEntityWithOwnerPrototype
	render_layer = "floor-mechanics",
	picture = entity_sprite,

	-- EntityWithHealthPrototype
	max_health = 250,
	dying_explosion = "medium-explosion",
	corpse = "medium-remnants",

	-- EntityPrototype
	icon = __GRAPHICS_PATH__ .. "ic-icon-128.png",
	icon_size = 128,
	collision_box = { { -0.45, -0.45 }, { 0.45, 0.45 } },
	collision_mask = {
		layers = {
			item = true,
			object = true,
			player = true,
			water_tile = true,
		},
	},
	selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
	flags = {
		"player-creation",
		"placeable-neutral",
		"not-upgradable",
	},
	minable = { mining_time = 1, result = constants.ic_name },
	selection_priority = 40,
}

---@type data.ItemPrototype
local item = {
	-- Prototype Base
	type = "item",
	name = constants.ic_name,
	place_result = constants.ic_name,

	-- ItemPrototype
	stack_size = 50,
	icon = __GRAPHICS_PATH__ .. "ic-icon-128.png",
	icon_size = 128,
	order = "m",
	subgroup = "circuit-network",
}

data:extend({ ic, item })
