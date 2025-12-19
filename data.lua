local oc_lib = require("lib.core.orientation.orientation-class")

require("data.pin")
require("data.ic")
require("data.tech")

data:extend({
	{ type = "custom-event", name = "die-shrink-on_initialized" },
	{ type = "custom-event", name = "die-shrink-on_status" },
	{ type = "custom-event", name = "die-shrink-on_edge_status" },
	{ type = "custom-event", name = "die-shrink-on_edge_changed" },
	{ type = "custom-event", name = "die-shrink-on_orientation_changed" },
	{ type = "custom-event", name = "die-shrink-on_children_normalized" },
	{ type = "custom-event", name = "die-shrink-on_pin_status" },
	{ type = "custom-event", name = "die-shrink-on_pin_immediate_voided" },
	{
		type = "custom-input",
		name = "die-shrink-click",
		key_sequence = "mouse-button-1",
	},
	{
		type = "custom-input",
		name = "die-shrink-linked-clear-cursor",
		key_sequence = "",
		linked_game_control = "clear-cursor",
	},
})

local PIN_OFFSET = 0.4

---@type things.ThingRegistration
local ic_registration = {
	name = "die-shrink-ic",
	intercept_construction = true,
	virtualize_orientation = oc_lib.OrientationClass.D8_0_RF,
	custom_events = {
		on_initialized = "die-shrink-on_initialized",
		on_status = "die-shrink-on_status",
		on_edge_status = "die-shrink-on_edge_status",
		on_children_normalized = "die-shrink-on_children_normalized",
		on_orientation_changed = "die-shrink-on_orientation_changed",
	},
	children = {
		[1] = {
			create = { name = "die-shrink-pin", position = { 0, 0 } },
			offset = { 0, -PIN_OFFSET },
			lifecycle_type = "real-real",
		},
		[2] = {
			create = { name = "die-shrink-pin", position = { 0, 0 } },
			offset = { PIN_OFFSET, -PIN_OFFSET },
			lifecycle_type = "real-real",
		},
		[3] = {
			create = { name = "die-shrink-pin", position = { 0, 0 } },
			offset = { PIN_OFFSET, 0 },
			lifecycle_type = "real-real",
		},
		[4] = {
			create = { name = "die-shrink-pin", position = { 0, 0 } },
			offset = { PIN_OFFSET, PIN_OFFSET },
			lifecycle_type = "real-real",
		},
		[5] = {
			create = { name = "die-shrink-pin", position = { 0, 0 } },
			offset = { 0, PIN_OFFSET },
			lifecycle_type = "real-real",
		},
		[6] = {
			create = { name = "die-shrink-pin", position = { 0, 0 } },
			offset = { -PIN_OFFSET, PIN_OFFSET },
			lifecycle_type = "real-real",
		},
		[7] = {
			create = { name = "die-shrink-pin", position = { 0, 0 } },
			offset = { -PIN_OFFSET, 0 },
			lifecycle_type = "real-real",
		},
		[8] = {
			create = { name = "die-shrink-pin", position = { 0, 0 } },
			offset = { -PIN_OFFSET, -PIN_OFFSET },
			lifecycle_type = "real-real",
		},
	},
}
data.raw["mod-data"]["things-names"].data["die-shrink-mux"] =
	ic_registration

---@type things.ThingRegistration
local pin_registration = {
	name = "die-shrink-pin",
	custom_blueprint_geometry = {
		[0] = { -0.3, -0.3, 0.09, 0.09 },
	},
	intercept_construction = false,
	no_garbage_collection = true,
	allow_in_cursor = "never",
	custom_events = {
		on_status = "die-shrink-on_pin_status",
		on_immediate_voided = "die-shrink-on_pin_immediate_voided",
	},
}
data.raw["mod-data"]["things-names"].data["die-shrink-pin"] =
	pin_registration
