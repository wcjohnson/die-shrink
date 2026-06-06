local constants = require("lib.constants")
local tlib = require("lib.core.table")
local data_util = require("lib.core.data-util")

-- Internal radar to keep editor surfaces charted.
---@type data.RadarPrototype
local radar = {
	type = "radar",
	name = constants.mod_prefix .. "-editor-radar",
	selectable_in_game = false,
	flags = {
		"not-on-map",
		"hide-alt-info",
		"not-blueprintable",
		"not-deconstructable",
	},
	hidden = true,
	hidden_in_factoriopedia = true,
	pictures = {
		count = 1,
		filename = __GRAPHICS_PATH__ .. "invisible.png",
		width = 1,
		height = 1,
		direction_count = 1,
	},
	collision_mask = { layers = {} },
	energy_per_nearby_scan = "250J",
	energy_per_sector = "1kW",
	energy_source = { type = "void" },
	energy_usage = "250W",
	max_distance_of_sector_revealed = 0,
	max_distance_of_nearby_sector_revealed = 1,
	localised_name = "",
	max_health = 1,
	connects_to_other_radars = false,
}
data:extend({ radar })

-- Internal energy source to power combinators on editor surfaces.
---@type data.ElectricEnergyInterfacePrototype
local energy_source = {
	type = "electric-energy-interface",
	name = constants.mod_prefix .. "-editor-energy-source",
	hidden_in_factoriopedia = true,
	energy_source = {
		type = "electric",
		render_no_power_icon = true,
		render_no_network_icon = true,
		usage_priority = "tertiary",
		output_flow_limit = "1YW",
		input_flow_limit = "0MW",
		buffer_capacity = "1RW",
	},
	picture = {
		count = 1,
		filename = __GRAPHICS_PATH__ .. "invisible.png",
		width = 1,
		height = 1,
		direction_count = 1,
	},
	energy_production = "1RW",
	gui_mode = "none",
	flags = {
		"not-on-map",
		"hide-alt-info",
		"not-blueprintable",
		"not-deconstructable",
	},
}
data:extend({ energy_source })

---@type data.WireConnectionPoint
local ZERO_CONNECTION_POINT = {
	wire = { green = { 0, 0 }, red = { 0, 0 } },
	shadow = { green = { 0, 0 }, red = { 0, 0 } },
}

---@type data.RotatedSprite
local pad_pictures = {
	layers = {
		data_util.sprite_to_rotated(
			data.raw["lamp"]["small-lamp"].picture_off.layers[1]
		),
		data_util.sprite_to_rotated(
			data.raw["lamp"]["small-lamp"].picture_off.layers[2]
		),
	},
}

-- Buildable internal pad to bond to external pins
---@type data.ElectricPolePrototype
local pad = {
	-- PrototypeBase
	type = "electric-pole",
	name = constants.pad_name,
	hidden_in_factoriopedia = true,

	-- ElectricPolePrototype
	supply_area_distance = 0,
	auto_connect_up_to_n_wires = 0,
	rewire_neighbours_when_destroying = false,
	connection_points = {
		ZERO_CONNECTION_POINT,
	},
	pictures = pad_pictures,
	maximum_wire_distance = constants.editor_surface_size,
	draw_copper_wires = false,
	draw_circuit_wires = true,

	-- EntityWithHealthPrototype
	max_health = 1,

	-- EntityPrototype
	icon = data.raw["lamp"]["small-lamp"].icon,
	icon_size = data.raw["lamp"]["small-lamp"].icon_size,
	collision_box = data.raw["lamp"]["small-lamp"].collision_box,
	collision_mask = data.raw["lamp"]["small-lamp"].collision_mask,
	selection_box = data.raw["lamp"]["small-lamp"].selection_box,
	fast_replaceable_group = nil,
	flags = {
		"not-on-map",
		"hide-alt-info",
		"not-upgradable",
		"no-automated-item-removal",
		"no-automated-item-insertion",
		"not-in-kill-statistics",
		"placeable-player",
		"player-creation",
	},
	minable = { mining_time = 1 },
	selection_priority = 70,
	allow_copy_paste = false,
}

-- Needed for pads to be blueprintable.
---@type data.ItemPrototype
local pad_item = {
	-- PrototypeBase
	type = "item",
	name = constants.pad_name,
	order = "f[iber-optics]",
	subgroup = "circuit-network",
	hidden_in_factoriopedia = true,

	-- ItemPrototype
	stack_size = 50,
	icon = data.raw["item"]["small-lamp"].icon,
	icon_size = data.raw["item"]["small-lamp"].icon_size,
	place_result = constants.pad_name,
	flags = { "hide-from-bonus-gui", "only-in-cursor" },
	weight = 0,
}

data:extend({ pad, pad_item })
