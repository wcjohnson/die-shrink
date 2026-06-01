local constants = require("lib.constants")

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

-- local radar = data.raw["radar"]["radar"]
-- if radar then
-- 	radar = table.deepcopy(radar)
-- 	radar.name = constants.mod_prefix .. "-editor-radar"
-- 	radar.hidden_in_factoriopedia = true
-- 	radar.pictures = {
-- 		count = 1,
-- 		filename = __GRAPHICS_PATH__ .. "invisible.png",
-- 		width = 1,
-- 		height = 1,
-- 		direction_count = 1,
-- 	}
-- 	radar.flags = {
-- 		"not-on-map",
-- 		"hide-alt-info",
-- 		"not-blueprintable",
-- 		"not-deconstructable",
-- 	}
-- 	data:extend({ radar })
-- end

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
		output_flow_limit = "2000MW",
		input_flow_limit = "0MW",
		buffer_capacity = "200MW",
	},
	picture = {
		count = 1,
		filename = __GRAPHICS_PATH__ .. "invisible.png",
		width = 1,
		height = 1,
		direction_count = 1,
	},
	energy_production = "2000MW",
	gui_mode = "none",
	flags = {
		"not-on-map",
		"hide-alt-info",
		"not-blueprintable",
		"not-deconstructable",
	},
}
data:extend({ energy_source })
