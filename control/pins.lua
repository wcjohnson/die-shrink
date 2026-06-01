-- Manage child pin entities.

local event = require("lib.core.event")
local strace = require("lib.core.strace")

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
