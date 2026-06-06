---Circuit connector pins.

local constants = require("lib.constants")
local data_util = require("lib.core.data-util")

---@type data.Sprite
local pin_sprite = {
	filename = __GRAPHICS_PATH__ .. "circle.png",
	size = 32,
	scale = 0.125,
	tint = { 1, 1, 1, 1 },
}

---@type data.RotatedSprite
local pin_pictures = {
	layers = {
		data_util.sprite_to_rotated(pin_sprite),
	},
}

---@type data.WireConnectionPoint
local ZERO_CONNECTION_POINT = {
	wire = { green = { 0, 0 }, red = { 0, 0 } },
	shadow = { green = { 0, 0 }, red = { 0, 0 } },
}

---@type data.ElectricPolePrototype
local pin = {
	-- PrototypeBase
	type = "electric-pole",
	name = constants.pin_name,
	hidden_in_factoriopedia = true,

	-- ElectricPolePrototype
	supply_area_distance = 0,
	auto_connect_up_to_n_wires = 0,
	rewire_neighbours_when_destroying = false,
	connection_points = {
		ZERO_CONNECTION_POINT,
	},
	pictures = pin_pictures,
	maximum_wire_distance = constants.circuit_wire_max_distance,
	draw_copper_wires = false,
	draw_circuit_wires = true,

	-- EntityWithHealthPrototype
	max_health = 1,

	-- EntityPrototype
	icon = __GRAPHICS_PATH__ .. "icon-jumper-wire.png",
	icon_size = 256,
	collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } },
	collision_mask = { layers = {} },
	selection_box = { { -0.1, -0.1 }, { 0.1, 0.1 } },
	fast_replaceable_group = nil,
	flags = {
		"placeable-off-grid",
		"not-on-map",
		"not-deconstructable",
		"hide-alt-info",
		"not-selectable-in-game",
		"not-upgradable",
		"no-automated-item-removal",
		"no-automated-item-insertion",
		"not-in-kill-statistics",
		"placeable-neutral",
		"player-creation",
	},
	minable = nil,
	selection_priority = 70,
	allow_copy_paste = false,
}

---@type data.ItemPrototype
local pin_item = {
	-- PrototypeBase
	type = "item",
	name = constants.pin_name,
	order = "f[iber-optics]",
	subgroup = "circuit-network",
	hidden_in_factoriopedia = true,

	-- ItemPrototype
	stack_size = 50,
	icon = __GRAPHICS_PATH__ .. "icon-jumper-wire.png",
	icon_size = 256,
	place_result = constants.pin_name,
	flags = { "hide-from-bonus-gui", "only-in-cursor" },
	weight = 0,
}

data:extend({ pin, pin_item })
