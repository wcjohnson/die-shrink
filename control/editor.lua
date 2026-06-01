local event = require("lib.core.event")
local constants = require("lib.constants")
local strace = require("lib.core.strace")

local EDITOR_SURFACE_PREFIX = "die-shrink-editor-p-"
local EDITOR_PANEL_NAME = "die-shrink-editor-panel"
local EDITOR_EXIT_BUTTON_NAME = "die-shrink-editor-exit"
local EDITOR_SIZE = 64
local EDITOR_ENTRY_MIN_ZOOM = 0.75
local EDITOR_ENERGY_SOURCE_NAME = constants.mod_prefix
	.. "-editor-energy-source"
local EDITOR_RADAR_NAME = constants.mod_prefix .. "-editor-radar"

local EDITOR_BLUEPRINT_AREA = {
	{ -EDITOR_SIZE / 2 - 1, -EDITOR_SIZE / 2 - 1 },
	{ EDITOR_SIZE / 2 + 1, EDITOR_SIZE / 2 + 1 },
}

local EDITOR_CHART_RADIUS = EDITOR_SIZE * 2
local EDITOR_CHART_AREA = {
	{ -EDITOR_CHART_RADIUS, -EDITOR_CHART_RADIUS },
	{ EDITOR_CHART_RADIUS, EDITOR_CHART_RADIUS },
}

local ALLOWED_ENTITY_NAMES = {
	["constant-combinator"] = true,
	["arithmetic-combinator"] = true,
	["decider-combinator"] = true,
	["selector-combinator"] = true,
}

local EDITOR_SYSTEM_ENTITY_NAMES = {
	[EDITOR_ENERGY_SOURCE_NAME] = true,
	[EDITOR_RADAR_NAME] = true,
}

---@param tags Tags?
---@return Tags
local function shallow_copy_tags(tags)
	local copy = {}
	if tags then
		for key, value in pairs(tags) do
			copy[key] = value
		end
	end
	return copy
end

---@class DieShrink.EditorStorage
---@field sessions {[uint]: DieShrink.EditorSession}
---@field surface_owners {[uint]: uint}

---@class DieShrink.EditorSession
---@field thing_id int64
---@field surface_name string

---@return DieShrink.EditorStorage
local function get_editor_storage()
	if not storage.editor then
		storage.editor = {
			sessions = {},
			surface_owners = {},
		}
	end
	return storage.editor
end

---@param surface LuaSurface?
---@return boolean
local function is_editor_surface(surface)
	if not surface or not surface.valid then return false end
	local editor_storage = storage.editor
	return editor_storage
			and editor_storage.surface_owners
			and editor_storage.surface_owners[surface.index] ~= nil
		or false
end

---@param player LuaPlayer
local function close_editor_panel(player)
	local panel = player.gui.left[EDITOR_PANEL_NAME]
	if panel then panel.destroy() end
end

---@param player LuaPlayer
local function open_editor_panel(player)
	close_editor_panel(player)

	local outer = player.gui.left.add({
		type = "frame",
		direction = "vertical",
		name = EDITOR_PANEL_NAME,
		caption = { "die-shrink-editor.title" },
	})
	local frame = outer.add({
		type = "frame",
		direction = "vertical",
		style = "inside_shallow_frame_with_padding",
	})

	local exit_flow = frame.add({ type = "flow", direction = "horizontal" })
	local exit_button = exit_flow.add({
		type = "button",
		name = EDITOR_EXIT_BUTTON_NAME,
		caption = { "die-shrink-editor.exit" },
		tooltip = { "die-shrink-editor.exit-tooltip" },
	})
	exit_button.style.width = 180

	local info = frame.add({
		type = "label",
		caption = { "die-shrink-editor.info" },
	})
	info.style.single_line = false
	info.style.maximal_width = 220
	info.style.top_margin = 8
end

---@param entity_name string
---@param player LuaPlayer?
---@param position MapPosition?
local function notify_not_allowed(entity_name, player, position)
	if not player or not player.valid then return end
	player.create_local_flying_text({
		text = {
			"die-shrink-editor.not-allowed-entity",
			{ "entity-name." .. entity_name },
		},
		position = position,
		create_at_cursor = not position,
		color = { r = 1.0, g = 0.35, b = 0.35, a = 1.0 },
		speed = 60,
	})
end

---@param entity LuaEntity
---@param player LuaPlayer?
local function handle_built_ghost(entity, player)
	if not entity.valid or entity.name ~= "entity-ghost" then return end
	local ghost_name = entity.ghost_name
	if ghost_name and ALLOWED_ENTITY_NAMES[ghost_name] then
		entity.silent_revive({ raise_revive = true })
		return
	end
	notify_not_allowed(ghost_name or "unknown", player, entity.position)
	entity.destroy()
end

---@param surface_name string
---@return LuaSurface
local function create_editor_surface(surface_name)
	local surface = game.create_surface(surface_name, {
		width = EDITOR_SIZE,
		height = EDITOR_SIZE,
		no_enemies_mode = true,
		property_expression_names = {},
		default_enable_all_autoplace_controls = false,
		autoplace_settings = {
			entity = { treat_missing_as_default = false, frequency = "none" },
			tile = { treat_missing_as_default = false },
			decorative = { treat_missing_as_default = false, frequency = "none" },
		},
	})

	surface.always_day = true
	surface.daytime = 0.5
	surface.freeze_daytime = true
	surface.show_clouds = false
	surface.request_to_generate_chunks({ 0, 0 }, 4)
	surface.force_generate_chunk_requests()
	surface.destroy_decoratives({})

	for _, force in pairs(game.forces) do
		force.set_surface_hidden(surface, true)
	end
	if not surface.has_global_electric_network then
		surface.create_global_electric_network()
	end

	local tile_name = prototypes.tile["refined-concrete"] and "refined-concrete"
		or "concrete"
	local tiles = {}
	for _, tile in
		ipairs(surface.find_tiles_filtered({
			position = { 0, 0 },
			radius = EDITOR_SIZE + 2,
		}))
	do
		local pos = tile.position
		if
			math.abs(pos.x) > EDITOR_SIZE / 2 or math.abs(pos.y) > EDITOR_SIZE / 2
		then
			tiles[#tiles + 1] = { name = "out-of-map", position = pos }
		else
			tiles[#tiles + 1] = { name = tile_name, position = pos }
		end
	end
	surface.set_tiles(tiles)

	return surface
end

---@param surface LuaSurface
---@param force string|integer|LuaForce
local function prepare_surface_for_force(surface, force)
	force.set_surface_hidden(surface, true)
	force.chart(surface, EDITOR_CHART_AREA)
end

---@param surface LuaSurface
---@param force string|integer|LuaForce
---@param name string
---@param position MapPosition
---@return LuaEntity?
local function ensure_single_editor_entity(surface, force, name, position)
	local entities =
		surface.find_entities_filtered({ name = name, force = force })
	local entity = nil
	for _, existing in ipairs(entities) do
		if not entity then
			entity = existing
		else
			existing.destroy()
		end
	end

	if not entity then
		entity = surface.create_entity({
			name = name,
			position = position,
			force = force,
		})
	end

	if entity then
		entity.destructible = false
		entity.operable = false
		entity.minable = false
	end

	return entity
end

---@param surface LuaSurface
---@param force string|integer|LuaForce
local function connect_editor_infra(surface, force)
	local source_proto = prototypes.entity[EDITOR_ENERGY_SOURCE_NAME]
	if source_proto then
		ensure_single_editor_entity(
			surface,
			force,
			EDITOR_ENERGY_SOURCE_NAME,
			{ EDITOR_SIZE / 2 + 4, 10 }
		)
	end

	local radar_proto = prototypes.entity[EDITOR_RADAR_NAME]
	if radar_proto then
		ensure_single_editor_entity(surface, force, EDITOR_RADAR_NAME, { 0, 0 })
	end
end

---@param player_index uint
---@return LuaSurface
local function get_or_create_editor_surface(player_index)
	local editor_storage = get_editor_storage()
	local surface_name = EDITOR_SURFACE_PREFIX .. tostring(player_index)
	local surface = game.get_surface(surface_name)
	if not surface or not surface.valid then
		surface = create_editor_surface(surface_name)
	end
	if not surface.has_global_electric_network then
		surface.create_global_electric_network()
	end
	editor_storage.surface_owners[surface.index] = player_index
	return surface
end

---@param surface LuaSurface
local function clear_editor_surface(surface)
	for _, entity in ipairs(surface.find_entities()) do
		if entity.valid and entity.type ~= "character" then
			if not entity.mine({ raise_destroyed = true, ignore_minable = true }) then
				entity.destroy()
			end
		end
	end
	for _, entity in ipairs(surface.find_entities()) do
		if entity.valid and entity.type ~= "character" then entity.destroy() end
	end
end

---@param surface LuaSurface
---@param force any
---@return string?
local function capture_editor_blueprint(surface, force)
	local inv = game.create_inventory(1)
	local bp = inv[1]
	bp.set_stack({ name = "blueprint", count = 1 })
	bp.create_blueprint({
		surface = surface,
		force = force,
		area = EDITOR_BLUEPRINT_AREA,
	})

	local content = nil
	if bp.is_blueprint_setup and bp.get_blueprint_entity_count() > 0 then
		content = bp.export_stack()
	end
	inv.destroy()
	return content
end

---@param bp_entities BlueprintEntity[]?
---@return MapPosition?
local function get_recentered_build_position(bp_entities)
	if not bp_entities then return nil end

	---@type number?
	local x1
	---@type number?
	local y1
	---@type number?
	local x2
	---@type number?
	local y2

	for _, bp_entity in pairs(bp_entities) do
		local proto = prototypes.entity[bp_entity.name]
		if proto and bp_entity.position then
			local direction = bp_entity.direction or defines.direction.north
			local w
			local h
			if
				direction == defines.direction.north
				or direction == defines.direction.south
			then
				w = proto.tile_width / 2
				h = proto.tile_height / 2
			else
				w = proto.tile_height / 2
				h = proto.tile_width / 2
			end

			local px = bp_entity.position.x
			local py = bp_entity.position.y
			if not x1 then
				x1 = px - w / 2
				y1 = py - h / 2
				x2 = px + w / 2
				y2 = py + h / 2
			else
				local bx1 = x1 --[[@as number]]
				local by1 = y1 --[[@as number]]
				local bx2 = x2 --[[@as number]]
				local by2 = y2 --[[@as number]]
				x1 = math.min(bx1, px - w / 2)
				y1 = math.min(by1, py - h / 2)
				x2 = math.max(bx2, px + w / 2)
				y2 = math.max(by2, py + h / 2)
			end
		end
	end

	if not x1 or not y1 or not x2 or not y2 then return nil end

	local width = x2 - x1
	local height = y2 - y1
	return {
		x = x1 + width / 2 - 0.1,
		y = y1 + height / 2 - 0.1,
	}
end

---@param surface LuaSurface
---@param force any
---@param blueprint string
local function restore_editor_blueprint(surface, force, blueprint)
	local inv = game.create_inventory(1)
	local bp = inv[1]
	bp.set_stack({ name = "blueprint", count = 1 })
	local import_result = bp.import_stack(blueprint)
	if import_result ~= 1 then
		local build_position = get_recentered_build_position(
			bp.get_blueprint_entities()
		) or { 0, 0 }
		local built = bp.build_blueprint({
			surface = surface,
			force = force,
			position = build_position,
			force_build = true,
			skip_fog_of_war = true,
		})
		if built then
			for _, entity in pairs(built) do
				if entity and entity.valid and entity.name == "entity-ghost" then
					handle_built_ghost(entity, nil)
				end
			end
		end
	end
	inv.destroy()
end

---@param player_index uint
---@param reason string
local function save_editor_session(player_index, reason)
	local editor_storage = get_editor_storage()
	---@type DieShrink.EditorSession?
	local session = editor_storage.sessions[player_index]
	if not session then return end
	editor_storage.sessions[player_index] = nil

	local player = game.get_player(player_index)
	if not player then return end
	close_editor_panel(player)

	local surface = game.get_surface(session.surface_name)
	if not surface or not surface.valid then return end

	local get_error, thing_raw = remote.call("things", "get", session.thing_id)
	if get_error or not thing_raw then return end
	---@type things.ThingSummary
	local thing = thing_raw

	local force = player.force --[[@as LuaForce]]

	---@type string?
	local blueprint = capture_editor_blueprint(surface, force)
	local set_error
	if blueprint then
		local blueprint_content = blueprint --[[@as string]]
		set_error = remote.call(
			"things",
			"set_tag",
			session.thing_id,
			"blueprint",
			blueprint_content
		)
	else
		local tags = shallow_copy_tags(thing.tags)
		tags.blueprint = nil
		set_error = remote.call("things", "set_tags", session.thing_id, tags)
	end
	strace.trace("editor-save", {
		reason = reason,
		player_index = player_index,
		thing_id = session.thing_id,
		has_blueprint = blueprint ~= nil,
		error = set_error,
	})
end

---@param player LuaPlayer
---@param thing things.ThingSummary
local function open_editor_for_thing(player, thing)
	local editor_storage = get_editor_storage()
	if editor_storage.sessions[player.index] then
		save_editor_session(player.index, "switch-ic")
	end

	local surface = get_or_create_editor_surface(player.index)
	prepare_surface_for_force(surface, player.force --[[@as LuaForce]])
	clear_editor_surface(surface)
	connect_editor_infra(surface, player.force --[[@as LuaForce]])

	local blueprint = thing.tags and thing.tags.blueprint
	if type(blueprint) == "string" and blueprint ~= "" then
		local blueprint_content = blueprint --[[@as string]]
		local player_force = player.force --[[@as LuaForce]]
		restore_editor_blueprint(surface, player_force, blueprint_content)
	end

	editor_storage.sessions[player.index] = {
		thing_id = thing.id,
		surface_name = surface.name,
	}

	open_editor_panel(player)
	player.set_controller({
		type = defines.controllers.remote,
		surface = surface,
		position = { 0, 0 },
	})
	if player.zoom < EDITOR_ENTRY_MIN_ZOOM then
		player.zoom = EDITOR_ENTRY_MIN_ZOOM
	end
end

event.bind("die-shrink-click", function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end

	local selected = player.selected
	if not selected or not selected.valid then return end
	if selected.name ~= constants.ic_name then return end

	local get_error, thing = remote.call("things", "get", selected)
	if get_error or not thing or not thing.entity then return end
	if thing.name ~= constants.ic_name then return end

	open_editor_for_thing(player, thing)
end)

event.bind(defines.events.on_gui_click, function(ev)
	local element = ev.element
	if not element or not element.valid then return end
	if element.name ~= EDITOR_EXIT_BUTTON_NAME then return end

	local player = game.get_player(ev.player_index)
	if not player then return end

	save_editor_session(ev.player_index, "exit-button")
	if player.controller_type == defines.controllers.remote then
		player.exit_remote_view()
	end
end)

event.bind(defines.events.on_player_controller_changed, function(ev)
	local editor_storage = storage.editor
	if not editor_storage or not editor_storage.sessions[ev.player_index] then
		return
	end

	local player = game.get_player(ev.player_index)
	if not player then return end
	if player.controller_type ~= defines.controllers.remote then
		save_editor_session(ev.player_index, "controller-left-remote")
	end
end)

event.bind(defines.events.on_player_changed_surface, function(ev)
	local editor_storage = storage.editor
	local session = editor_storage and editor_storage.sessions[ev.player_index]
	if not session then return end

	local player = game.get_player(ev.player_index)
	if not player then return end
	if player.surface.name ~= session.surface_name then
		save_editor_session(ev.player_index, "surface-changed")
	end
end)

event.bind(
	defines.events.on_pre_player_left_game,
	function(ev) save_editor_session(ev.player_index, "left-game") end
)

event.bind(defines.events.on_marked_for_deconstruction, function(ev)
	local entity = ev.entity
	if
		not entity
		or not entity.valid
		or not is_editor_surface(entity.surface)
	then
		return
	end
	local player = ev.player_index and game.get_player(ev.player_index) or nil

	if EDITOR_SYSTEM_ENTITY_NAMES[entity.name] then
		entity.cancel_deconstruction(entity.force, player)
		return
	end

	entity.destroy({ raise_destroy = true, player = player })
end)

---@param entity LuaEntity
---@param player_index uint?
local function handle_editor_surface_build(entity, player_index)
	if
		not entity
		or not entity.valid
		or not is_editor_surface(entity.surface)
	then
		return
	end
	if entity.name ~= "entity-ghost" then return end

	local player = player_index and game.get_player(player_index) or nil
	handle_built_ghost(entity, player)
end

event.bind(
	defines.events.on_built_entity,
	function(ev) handle_editor_surface_build(ev.entity, ev.player_index) end
)

event.bind(
	defines.events.on_robot_built_entity,
	function(ev) handle_editor_surface_build(ev.entity, nil) end
)

event.bind(
	defines.events.script_raised_built,
	function(ev) handle_editor_surface_build(ev.entity, nil) end
)

event.bind(
	defines.events.script_raised_revive,
	function(ev) handle_editor_surface_build(ev.entity, nil) end
)
