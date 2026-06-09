local constants = require("lib.constants")

--------------------------------------------------------------------------------
-- IC
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- POWER CONSUMER
--------------------------------------------------------------------------------

---@type data.Sprite
local invisible_sprite = {
	filename = __GRAPHICS_PATH__ .. "invisible.png",
	width = 1,
	height = 1,
}

---@type data.LampPrototype
local power_consumer = {
	-- PrototypeBase
	name = constants.mod_prefix .. "-power-consumer",
	type = "lamp",
	hidden_in_factoriopedia = true,

	-- EntityPrototype
	minable = nil,
	collision_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
	selection_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
	max_health = 1000,
	collision_mask = { layers = {} },
	flags = {
		"hide-alt-info",
		"not-on-map",
		"not-upgradable",
		"not-blueprintable",
		"not-deconstructable",
		"placeable-off-grid",
	},
	selection_priority = 10,
	selectable_in_game = false,
	allow_copy_paste = false,
	created_smoke = nil,

	-- LampPrototype
	picture_on = { layers = { invisible_sprite } },
	picture_off = { layers = { invisible_sprite } },
	always_on = true,

	energy_usage_per_tick = "5kW",
	energy_source = { type = "electric", usage_priority = "secondary-input" },
	circuit_wire_connection_point = nil,
	draw_copper_wires = false,
	draw_circuit_wires = false,
}

data:extend({ power_consumer })
