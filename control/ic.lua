local class = require("lib.core.class").class
local event = require("lib.core.event")
local ovl_lib = require("lib.core.overlay")
local pos_lib = require("lib.core.math.pos")
local constants = require("lib.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local strace = require("lib.core.strace")
local compiler = require("control.compiler")
local linker = require("control.linker")
local option_lib = require("control.option")
local tlib = require("lib.core.table")

local type = type
local tonumber = tonumber
local EMPTY = tlib.EMPTY

---@class DieShrink.IC
---@field thing_id ThingID
---@field alive boolean
---@field n_pins uint
---@field pin_labels {[uint]: string} Labels for pins, indexed by pin number
---@field option_definitions {string: [DieShrink.OptionDefinition, uint]}
---@field option_choices {string: DieShrink.OptionChoice}
---@field linked? DieShrink.LinkerResult Linker result for this IC.
local IC = class("DieShrink.IC")
_G.IC = IC

function IC:new(thing_id)
	local obj = setmetatable({
		thing_id = thing_id,
		n_pins = 0,
		alive = false,
		pin_labels = {},
		option_definitions = {},
		option_choices = {},
	}, self)
	local ics = storage.ics
	if not ics then
		ics = {}
		storage.ics = ics
	end
	ics[thing_id] = obj
	return obj
end

---Apply options to linked constant combs.
function IC:apply_options()
	if not self.linked then return end
	for key, option_info in pairs(self.option_definitions or {}) do
		local option_def = option_info[1]
		local entity_index = option_info[2]
		local entity = self.linked.entities and self.linked.entities[entity_index]
		local choice = self.option_choices and self.option_choices[key]
		strace.trace(
			"IC",
			self.thing_id,
			"applying option",
			key,
			"with choice",
			choice,
			"to entity",
			entity
		)
		option_lib.apply_option_to_combinator(entity, option_def, choice)
	end
end

---Compile and link the IC.
function IC:link(force_recompile)
	strace.trace("Linking IC", self.thing_id)
	if force_recompile then
		strace.trace("Unlinking IC", self.thing_id, "due to force recompile")
		self:unlink()
	end
	if self.linked then
		strace.trace("IC", self.thing_id, "is already linked, skipping")
		return
	end
	if self.n_pins == 0 then
		strace.trace("IC", self.thing_id, "has not been configured yet.")
		return
	end
	local _, thing = remote.call("things", "get", self.thing_id)
	if (not thing) or thing.status ~= "real" then
		strace.info("IC", self.thing_id, "is not real, skipping link")
		return
	end
	local bp_string = thing.tags and thing.tags.blueprint --[[@as string?]]
	if not bp_string then
		strace.trace("IC", self.thing_id, "is empty")
		return
	end
	local option_choices = thing.tags and thing.tags.option --[[@as DieShrink.OptionChoices]]
		or {}
	self.option_choices = option_choices
	local _, children = remote.call("things", "get_children", thing.id)
	if not children then
		strace.error("IC", self.thing_id, "is missing children")
		return
	end
	local pin_entities = tlib.t_map_t(
		children,
		function(key, child) return tonumber(key), child.entity end
	) --[[@as table<uint, LuaEntity>]]
	if #pin_entities ~= self.n_pins then
		strace.error(
			"Number of child entities",
			#pin_entities,
			"does not match n_pins",
			self.n_pins,
			"for IC with thing_id",
			self.thing_id
		)
		return
	end
	local compiled = compiler.compile(bp_string, option_choices)
	if not compiled then
		strace.error("Failed to compile IC with thing_id", self.thing_id)
		return
	end
	self.pin_labels = compiled.labels or {}
	self.option_definitions = compiled.options or {}
	strace.trace(
		"Compiled IC",
		self.thing_id,
		"with",
		#compiled.entities,
		"entities and",
		#compiled.wires,
		"wires"
	)
	strace.trace(
		"Compiled to",
		function()
			return serpent.line(
				compiled,
				{ maxlevel = 10, comment = false, nocode = true }
			)
		end
	)
	self.linked = linker.link(
		compiled,
		thing.entity.surface,
		thing.entity.force --[[@as LuaForce]],
		thing.entity.position,
		pin_entities
	)
	event.raise("dieshrink.ic_compiled", self)
end

---Destroy compiled circuit and links
function IC:unlink()
	if self.linked then
		linker.unlink(self.linked)
		self.linked = nil
	end
end

---Disconnect pin wires from linked circuit.
function IC:disconnect_pins()
	if not self.linked then return end
	linker.disconnect(self.linked)
end

---Reconnect pin wires to linked circuit.
function IC:reconnect_pins()
	if not self.linked then return end
	linker.reconnect(self.linked)
end

function IC:get_n_pins() return self.n_pins end

---@return string?
function IC:get_label()
	local _, value =
		remote.call("things-tags-v1", "get_tag", self.thing_id, "label")
	if type(value) ~= "string" or value == "" then return nil end
	return value
end

---@param label string?
function IC:set_label(label)
	if type(label) ~= "string" or label == "" then label = nil end
	remote.call(
		"things-tags-v1",
		"set_tag",
		self.thing_id,
		"label",
		label --[[@as any]]
	)
end

---@return SignalID[]?
function IC:get_icons()
	local _, value =
		remote.call("things-tags-v1", "get_tag", self.thing_id, "icons")
	if type(value) ~= "table" or (not next(value)) then return nil end
	return value
end

---@param icons SignalID[]?
function IC:set_icons(icons)
	if #icons == 0 then icons = nil end
	remote.call(
		"things-tags-v1",
		"set_tag",
		self.thing_id,
		"icons",
		icons --[[@as any]]
	)
end

function IC:set_n_pins(n)
	if self.n_pins == n then return end
	if self.n_pins ~= 0 then
		strace.error(
			"Attempted to change number of pins on IC",
			self.thing_id,
			"from",
			self.n_pins,
			"to",
			n
		)
		return
	end
	self.n_pins = n
	event.raise("dieshrink.ic_pins_changed", self)
end

function IC:destroy()
	self:unlink()
	storage.ics[self.thing_id] = nil
end

---@param key string
---@param choice DieShrink.OptionChoice
function IC:set_option_choice(key, choice)
	local _, opts =
		remote.call("things-tags-v1", "get_tag", self.thing_id, "option")
	local next_choices = opts or {}
	next_choices[key] = choice
	strace.trace(
		"IC:set_option_choice for",
		self.thing_id,
		key,
		choice,
		": setting option tag to",
		next_choices
	)
	remote.call(
		"things-tags-v1",
		"set_tag",
		self.thing_id,
		"option",
		next_choices
	)
end

---@param signal (SignalID|SignalFilter)
---@return string
local function signal_to_sprite(signal)
	local ty = signal.type
	if ty == "virtual" then
		return "virtual-signal/" .. signal.name
	elseif ty == nil then
		return "item/" .. signal.name
	else
		return ty .. "/" .. signal.name
	end
end

local ICON_LAYOUTS = {
	[1] = {
		scale = 0.95,
		offsets = {
			{ 0, 0 },
		},
	},
	[2] = {
		scale = 0.5,
		offsets = {
			{ -0.24, 0 },
			{ 0.24, 0 },
		},
	},
	[3] = {
		scale = 0.4,
		offsets = {
			{ -0.24, -0.24 },
			{ 0.24, -0.24 },
			{ -0.24, 0.24 },
		},
	},
	[4] = {
		scale = 0.4,
		offsets = {
			{ -0.24, -0.24 },
			{ 0.24, -0.24 },
			{ -0.24, 0.24 },
			{ 0.24, 0.24 },
		},
	},
}

function IC:apply_icons()
	local icons = self:get_icons() or EMPTY
	local icon_count = #icons
	if icon_count > 4 then icon_count = 4 end
	if icon_count == 0 then icon_count = 1 end
	local layout = ICON_LAYOUTS[icon_count] or ICON_LAYOUTS[1]
	local _, thing = remote.call("things-metadata-v1", "get", self.thing_id)
	if not thing then return end
	local entity = thing.entity
	if not entity then return end
	for i = 1, 4 do
		local signal = icons[i]
		local ro = nil
		if signal then
			local offset = layout.offsets[i] or { 0, 0 }
			ro = rendering.draw_sprite({
				sprite = signal_to_sprite(signal),
				surface = entity.surface,
				target = { entity = entity, offset = offset },
				x_scale = layout.scale,
				y_scale = layout.scale,
				render_layer = "lower-object",
			})
		end
		remote.call(
			"things-render-object-v1",
			"attach_render_object",
			self.thing_id,
			"icon" .. i,
			ro
		)
	end
end

--------------------------------------------------------------------------------
-- IC LIFECYCLE
--------------------------------------------------------------------------------

event.bind(
	"die-shrink-on_initialized",
	---@param thing things.EventData.on_initialized
	function(thing)
		-- Create IC state
		local ic = get_or_create_ic_state(thing.id)
		-- Initial n_pins
		local n_pins_tag = thing.tags and thing.tags.n_pins
		if n_pins_tag then
			ic.n_pins = n_pins_tag --[[@as uint]]
		else
			local _, n_children = remote.call("things", "get_num_children", thing.id)
			n_children = n_children or 0
			if n_children > 8 then
				n_children = 16
			elseif n_children > 4 then
				n_children = 8
			elseif n_children > 2 then
				n_children = 4
			elseif n_children > 0 then
				n_children = 2
			else
				n_children = 0
			end
			ic.n_pins = n_children
		end
		strace.trace("Initialized ic", ic.thing_id, "with", ic.n_pins, "pins")
		-- Create pins
		check_pins(thing, ic:get_n_pins(), ic)
		-- If real, compile
		if thing.status == "real" then
			strace.trace("Linking IC", ic.thing_id, "due to built as real")
			ic:link()
			ic:apply_icons()
		end
	end
)

event.bind("dieshrink.ic_pins_changed", function(ic)
	local _, thing = remote.call("things", "get", ic.thing_id)
	if not thing then return end
	local n_pins = ic:get_n_pins()
	remote.call("things", "set_tag", thing.id, "n_pins", n_pins)
	check_pins(thing, n_pins, ic)
end)

event.bind(
	"die-shrink-on_status",
	---@param ev things.EventData.on_status
	function(ev)
		strace.trace("die-shrink-on_status", ev)
		local old_status = ev.old_status
		local new_status = ev.new_status
		local ic = get_or_create_ic_state(ev.thing.id)

		if new_status == "destroyed" then
			ic:destroy()
			return
		end

		-- Check pins in all non-void states
		if
			old_status == "void"
			or new_status == "ghost"
			or new_status == "real"
		then
			check_pins(ev.thing, ic:get_n_pins(), ic)
		end

		-- Unlink if void or ghosted
		if new_status == "void" or new_status == "ghost" then
			strace.trace(
				"Unlinking IC",
				ic.thing_id,
				"due to status change to",
				new_status
			)
			ic:unlink()
		end

		-- Link if real
		if new_status == "real" then
			strace.trace("Linking IC", ic.thing_id, "due to status change to real")
			ic:link()
			ic:apply_icons()
		end
	end
)

event.bind("dieshrink.ic_children_normalized", function(ic)
	local _, status = remote.call("things-metadata-v1", "get_status", ic.thing_id)
	if status == "real" then
		-- Pins changed so recompile.
		-- TODO: make more efficient; we don't really need full recompile?
		strace.trace("Recompiling IC", ic.thing_id, "due to children normalized")
		ic:link(true)
	else
		ic:unlink()
	end
end)

event.bind(
	"die-shrink-on_tags_changed",
	---@param ev things.EventData.on_tags_changed
	function(ev)
		local ic = get_ic_state(ev.thing.id)
		if not ic then return end
		if
			(ev.new_tags and ev.new_tags.blueprint or "")
			~= (ev.old_tags and ev.old_tags.blueprint or "")
		then
			strace.trace("Blueprint tag changed for IC", ic.thing_id, "relinking")
			ic:link(true)
			return
		end

		-- TODO: consider diffing here?
		ic.option_choices = ev.new_tags and ev.new_tags.option --[[@as DieShrink.OptionChoices]]
			or {}
		ic:apply_options()
		ic:apply_icons()
		event.raise("dieshrink.ic_options_changed", ic)
		event.raise("dieshrink.ic_labels_changed", ic)
	end
)

return IC
