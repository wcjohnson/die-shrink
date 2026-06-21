local oc_lib = require("lib.core.orientation.orientation-class")

-- Bootstrap Relm data phase
_G.__RELM_GRAPHICS_PATH__ = "__die-shrink__/lib/core/relm/graphics/"
require("lib.core.relm.relm_data")

require("data.pin")
require("data.ic")
require("data.tech")
require("data.internal")
require("data.compiler")

data:extend({
	{ type = "custom-event", name = "die-shrink-on_initialized" },
	{ type = "custom-event", name = "die-shrink-on_status" },
	{ type = "custom-event", name = "die-shrink-on_orientation_changed" },
	{ type = "custom-event", name = "die-shrink-on_children_normalized" },
	{ type = "custom-event", name = "die-shrink-on_tags_changed" },
	{ type = "custom-event", name = "die-shrink-on_pin_status" },
	{ type = "custom-event", name = "die-shrink-on_pin_immediate_voided" },
	{ type = "custom-event", name = "die-shrink-on_editor_thing_initialized" },
	{ type = "custom-event", name = "die-shrink-on_editor_thing_tags_changed" },
	{
		type = "custom-input",
		name = "die-shrink-click",
		key_sequence = "mouse-button-1",
	},
})

local thing_registrations = data.raw["mod-data"]["things-names"].data

---@type things.ThingRegistration
local ic_registration = {
	name = "die-shrink-ic",
	intercept_construction = true,
	virtualize_orientation = oc_lib.OrientationClass.D8_0_RF,
	custom_events = {
		on_initialized = "die-shrink-on_initialized",
		on_status = "die-shrink-on_status",
		on_children_normalized = "die-shrink-on_children_normalized",
		on_orientation_changed = "die-shrink-on_orientation_changed",
		on_tags_changed = "die-shrink-on_tags_changed",
	},
}
thing_registrations["die-shrink-ic"] = ic_registration

---@type things.ThingRegistration
local pin_registration = {
	name = "die-shrink-pin",
	intercept_construction = false,
	no_garbage_collection = true,
	allow_in_cursor = "never",
	custom_events = {
		on_status = "die-shrink-on_pin_status",
		on_immediate_voided = "die-shrink-on_pin_immediate_voided",
	},
}
thing_registrations["die-shrink-pin"] = pin_registration

---@type things.ThingRegistration
local pad_registration = {
	name = "die-shrink-pad",
	intercept_construction = true,
	custom_events = {
		on_initialized = "die-shrink-on_editor_thing_initialized",
		on_tags_changed = "die-shrink-on_editor_thing_tags_changed",
	},
}
thing_registrations["die-shrink-pad"] = pad_registration

---@type things.ThingRegistration
local option_registration = {
	name = "die-shrink-option",
	intercept_construction = true,
	custom_events = {
		on_initialized = "die-shrink-on_editor_thing_initialized",
		on_tags_changed = "die-shrink-on_editor_thing_tags_changed",
	},
}
thing_registrations["die-shrink-option"] = option_registration
