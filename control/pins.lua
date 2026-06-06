-- Manage child pin entities.

local event = require("lib.core.event")
local strace = require("lib.core.strace")
local orientation_lib = require("lib.core.orientation.orientation")
local pos_lib = require("lib.core.math.pos")
local constants = require("lib.constants")

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

local function create_pin_thing(parent, child_entity, index, num, offset)
	remote.call("things", "create_thing", {
		entity = child_entity,
		parent = parent.id,
		child_index = index,
		relative_pos = offset,
		tags = {
			n = num,
		},
	})
end

local function devoid_pin_thing(child_id, child_entity)
	remote.call("things", "create_thing", {
		devoid = child_id,
		entity = child_entity,
	})
end

---Check an IC for correct number and placement of pins, creating or destroying pin entities as needed.
---@param parent things.ThingSummary
---@param n_pins 0|2|4|8|16
---@param ic DieShrink.IC
function _G.check_pins(parent, n_pins, ic)
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
				create_pin_thing(parent, child_entity, pin_index, i, pin_offset)
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
