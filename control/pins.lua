-- Manage child pin entities.

local event = require("lib.core.event")
local strace = require("lib.core.strace")
local orientation_lib = require("lib.core.orientation.orientation")
local pos_lib = require("lib.core.math.pos")
local constants = require("lib.constants")

---@param pin LuaEntity?
local function disconnect_one_pin_entirely(pin)
	if not pin then return end
	local reds =
		pin.get_wire_connector(defines.wire_connector_id.circuit_red, false)
	local greens =
		pin.get_wire_connector(defines.wire_connector_id.circuit_green, false)
	if reds then reds.disconnect_all(defines.wire_origin.script) end
	if greens then greens.disconnect_all(defines.wire_origin.script) end
end

---@param from_pin LuaEntity?
---@param to_pin LuaEntity?
local function connect_one_pin(from_pin, to_pin)
	if not from_pin or not to_pin then return end
	local reds_from =
		from_pin.get_wire_connector(defines.wire_connector_id.circuit_red, true)
	local greens_from =
		from_pin.get_wire_connector(defines.wire_connector_id.circuit_green, true)
	local reds_to =
		to_pin.get_wire_connector(defines.wire_connector_id.circuit_red, true)
	local greens_to =
		to_pin.get_wire_connector(defines.wire_connector_id.circuit_green, true)
	if reds_from and reds_to then
		reds_from.connect_to(reds_to, false, defines.wire_origin.script)
	end
	if greens_from and greens_to then
		greens_from.connect_to(greens_to, false, defines.wire_origin.script)
	end
end

---@param from_pin LuaEntity?
---@param to_pin LuaEntity?
local function disconnect_one_pin(from_pin, to_pin)
	if not from_pin or not to_pin then return end
	local reds_from =
		from_pin.get_wire_connector(defines.wire_connector_id.circuit_red, true)
	local greens_from =
		from_pin.get_wire_connector(defines.wire_connector_id.circuit_green, true)
	local reds_to =
		to_pin.get_wire_connector(defines.wire_connector_id.circuit_red, true)
	local greens_to =
		to_pin.get_wire_connector(defines.wire_connector_id.circuit_green, true)
	if reds_from and reds_to then
		reds_from.disconnect_from(reds_to, defines.wire_origin.script)
	end
	if greens_from and greens_to then
		greens_from.disconnect_from(greens_to, defines.wire_origin.script)
	end
end

---Remove all script wires connecting pins to other pins.
---@param pins {[string|int]: things.ThingSummary}?
local function disconnect_all_pins_entirely(pins)
	if not pins then return end
	for index, child_summary in pairs(pins) do
		disconnect_one_pin_entirely(child_summary.entity)
	end
end

---@param from_pins {[string|int]: things.ThingSummary}?
---@param to_pins {[string|int]: things.ThingSummary}?
local function connect_each_pin(from_pins, to_pins)
	if not from_pins or not to_pins then return end
	for from_index, from_pin_summary in pairs(from_pins) do
		local to_pin_summary = to_pins[from_index]
		if to_pin_summary then
			connect_one_pin(from_pin_summary.entity, to_pin_summary.entity)
		end
	end
end

---@param from_pins {[string|int]: things.ThingSummary}?
---@param to_pins {[string|int]: things.ThingSummary}?
local function disconnect_each_pin(from_pins, to_pins)
	if not from_pins or not to_pins then return end
	for from_index, from_pin_summary in pairs(from_pins) do
		local to_pin_summary = to_pins[from_index]
		if to_pin_summary then
			disconnect_one_pin(from_pin_summary.entity, to_pin_summary.entity)
		end
	end
end

---@param my_pins {[string|int]: things.ThingSummary}?
---@param neighbor_id uint64?
local function connect_one_neighbor(my_pins, neighbor_id)
	if not my_pins or not neighbor_id then return end
	local _, neighbor = remote.call("things", "get", neighbor_id)
	if not neighbor or neighbor.status ~= "real" then return end
	local _, neighbor_pins = remote.call("things", "get_children", neighbor_id)
	connect_each_pin(my_pins, neighbor_pins)
end

--------------------------------------------------------------------------------
-- DYNAMIC PIN CREATION
--------------------------------------------------------------------------------

local PIN_OFFSET = 0.4
local INNER_PIN_OFFSET = 0.2

local pin_layouts = {
	[0] = {},
	[2] = { { -PIN_OFFSET, 0 }, { PIN_OFFSET, 0 } },
	[4] = {
		{ 0, -PIN_OFFSET },
		{ PIN_OFFSET, 0 },
		{ 0, PIN_OFFSET },
		{ -PIN_OFFSET, 0 },
	},
	[8] = {
		{ 0, -PIN_OFFSET },
		{ PIN_OFFSET, -PIN_OFFSET },
		{ PIN_OFFSET, 0 },
		{ PIN_OFFSET, PIN_OFFSET },
		{ 0, PIN_OFFSET },
		{ -PIN_OFFSET, PIN_OFFSET },
		{ -PIN_OFFSET, 0 },
		{ -PIN_OFFSET, -PIN_OFFSET },
	},
	[16] = {
		{ 0, -PIN_OFFSET },
		{ PIN_OFFSET, -PIN_OFFSET },
		{ PIN_OFFSET, 0 },
		{ PIN_OFFSET, PIN_OFFSET },
		{ 0, PIN_OFFSET },
		{ -PIN_OFFSET, PIN_OFFSET },
		{ -PIN_OFFSET, 0 },
		{ -PIN_OFFSET, -PIN_OFFSET },
		{ 0, -INNER_PIN_OFFSET },
		{ INNER_PIN_OFFSET, -INNER_PIN_OFFSET },
		{ INNER_PIN_OFFSET, 0 },
		{ INNER_PIN_OFFSET, INNER_PIN_OFFSET },
		{ 0, INNER_PIN_OFFSET },
		{ -INNER_PIN_OFFSET, INNER_PIN_OFFSET },
		{ -INNER_PIN_OFFSET, 0 },
		{ -INNER_PIN_OFFSET, -INNER_PIN_OFFSET },
	},
}

---@param parent_pos MapPosition
---@param parent_orientation Core.Orientation?
---@param offset MapPosition
---@return MapPosition
local function offset_pos(parent_pos, parent_orientation, offset)
	if parent_orientation then
		offset = orientation_lib.transform_vector(parent_orientation, offset)
	end
	local offset_x, offset_y = pos_lib.pos_get(offset)
	local parent_x, parent_y = pos_lib.pos_get(parent_pos)
	return { parent_x + offset_x, parent_y + offset_y }
end

---@param parent_entity LuaEntity
---@param pos MapPosition
local function create_pin_entity(parent_entity, pos)
	return parent_entity.surface.create_entity({
		name = constants.pin_name,
		position = pos,
		force = parent_entity.force,
		raise_built = false,
		create_build_effect_smoke = false,
	})
end

local function create_pin_thing(parent, child_entity, index, offset)
	remote.call("things", "create_thing", {
		entity = child_entity,
		parent = parent.id,
		child_index = index,
		relative_pos = offset,
	})
end

local function devoid_pin_thing(child_id, child_entity)
	remote.call("things", "create_thing", {
		devoid = child_id,
		entity = child_entity,
	})
end

---@param parent things.ThingSummary
---@param n_pins 0|2|4|8|16
---@param ic DieShrink.IC
local function check_pins(parent, n_pins, ic)
	local pin_layout = pin_layouts[n_pins]
	if not pin_layout then
		error("LOGIC ERROR: invalid number of pins: " .. n_pins)
		return
	end

	local did_work = false
	local parent_pos = parent.entity.position
	local parent_status = parent.status
	local child_should_live = parent_status == "real" or parent_status == "ghost"

	local _, children = remote.call("things", "get_children", parent.id)
	for i = 1, n_pins do
		local pin_index = tostring(i)
		local pin_offset = pin_layout[i]
		local child = children and children[pin_index]

		if (not child) and child_should_live then
			-- Must create entity and thing
			local child_pos =
				offset_pos(parent_pos, parent.virtual_orientation, pin_offset)
			local child_entity = create_pin_entity(parent.entity, child_pos)
			if child_entity then
				create_pin_thing(parent, child_entity, pin_index, pin_offset)
				strace.trace("created pin", pin_index, "of cpu", parent.id)
				did_work = true
			else
				strace.error("Failed to create pin entity for thing", parent.id)
			end
		elseif child and (child.status == "void") and child_should_live then
			-- Must create entity and devoid thing
			local child_pos =
				offset_pos(parent_pos, parent.virtual_orientation, pin_offset)
			local child_entity = create_pin_entity(parent.entity, child_pos)
			if child_entity then
				devoid_pin_thing(child.id, child_entity)
				strace.trace("devoided pin", pin_index, "of cpu", parent.id)
				did_work = true
			else
				strace.error("Failed to create pin entity for thing", parent.id)
			end
		elseif child and (child.status ~= "void") and not child_should_live then
			remote.call("things", "void", child.id)
			did_work = true
		end
	end

	if did_work then event.raise("dieshrink.ic_children_normalized", ic) end
end

event.bind(
	"die-shrink-on_initialized",
	---@param thing things.EventData.on_initialized
	function(thing)
		-- Create IC state
		local ic = IC:new(thing.id)
		-- Initial n_pins
		local n_pins_tag = thing.tags and thing.tags.n_pins
		if n_pins_tag then
			ic.n_pins = n_pins_tag
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
		local ic = get_ic_state(ev.thing.id)

		if new_status == "destroyed" then
			-- Destroy IC state
			if ic then ic:destroy() end
			return
		end

		if
			old_status == "void"
			or new_status == "ghost"
			or new_status == "real"
		then
			-- Check pins in all non-void states
			if ic then check_pins(ev.thing, ic:get_n_pins(), ic) end
		end

		-- local entity, ic = get_ic_info(ev.thing, false)

		if ev.old_status == "ghost" and ev.new_status == "real" then
			-- Connect to all neighbors on revival.
		end
	end
)

--------------------------------------------------------------------------------
-- PIN LABELS
--------------------------------------------------------------------------------

-- Render pin labels when selecting a pin or mux entity.
event.bind(
	defines.events.on_selected_entity_changed,
	---@param ev EventData.on_selected_entity_changed
	function(ev)
		local player = game.get_player(ev.player_index)
		local player_state = get_or_create_player_state(ev.player_index)
		if not player or not player_state then return end
		local selected = player.selected
		player_state:clear_pin_labels()
		if not selected then return end
		local _, selected_thing = remote.call("things", "get", selected)
		if
			not selected_thing
			or not (
				selected_thing.name == "die-shrink-pin"
				or selected_thing.name == "die-shrink-ic"
			)
		then
			return
		end
		if selected_thing.name == "die-shrink-pin" then
			if selected_thing.parent then
				_, selected_thing =
					remote.call("things", "get", selected_thing.parent[1])
			else
				return
			end
		end
		if not selected_thing then return end
		player_state:render_pin_labels(selected_thing, nil)
	end
)

-- When mux orientation changes, pin labels need to be redrawn for all players
-- that have them shown.
event.bind(
	"die-shrink-on_orientation_changed",
	---@param ev things.EventData.on_orientation_changed
	function(ev)
		strace.trace("die-shrink-on_orientation_changed", ev)
		local entity = ev.thing.entity
		if not entity then return end
		for _, player in pairs(game.connected_players) do
			if player.selected == entity then
				local player_state = get_or_create_player_state(player.index)
				if player_state then player_state:render_pin_labels(ev.thing, nil) end
			end
		end
	end
)

--------------------------------------------------------------------------------
-- SUPPRESS CONTAINER GUI
-- If a pin is clicked, close the resulting container GUI.
--------------------------------------------------------------------------------

event.bind(
	defines.events.on_gui_opened,
	---@param ev EventData.on_gui_opened
	function(ev)
		if ev.gui_type ~= defines.gui_type.entity then return end
		local entity = ev.entity
		if not entity then return end
		local player = game.get_player(ev.player_index)
		if not player then return end
		local name = entity.type == "entity-ghost" and entity.ghost_name
			or entity.name
		if name ~= "die-shrink-pin" then return end
		player.opened = nil
	end
)

--------------------------------------------------------------------------------
-- CLEAR ORPHANED PINS
--------------------------------------------------------------------------------

commands.add_command(
	"die-shrink-clear-orphaned-pins",
	"Clear orphaned pin entities.",
	function(cmd)
		local count = 0
		for _, surface in pairs(game.surfaces) do
			local pins = surface.find_entities_filtered({ name = "die-shrink-pin" })
			for _, pin in pairs(pins) do
				local _, thing = remote.call("things", "get", pin)
				if thing then
					if not thing.parent then
						remote.call("things", "force_destroy", thing.id)
						count = count + 1
					end
				else
					pin.destroy()
					count = count + 1
				end
			end
		end
		game.print({ "", "Destroyed ", count, " orphaned pins" })
	end
)
