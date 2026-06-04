--------------------------------------------------------------------------------
-- Circuit editor
--------------------------------------------------------------------------------

local class = require("lib.core.class").class
local event = require("lib.core.event")
local constants = require("lib.constants")
local strace = require("lib.core.strace")
local counters = require("lib.core.counters")
local tlib = require("lib.core.table")

local EMPTY = tlib.EMPTY

local EDITOR_SURFACE_PREFIX = "die-shrink-editor-s-"
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
	[constants.pad_name] = true,
	[constants.ic_name] = true,
	[constants.pin_name] = true,
}

local EDITOR_SYSTEM_ENTITY_NAMES = {
	[EDITOR_ENERGY_SOURCE_NAME] = true,
	[EDITOR_RADAR_NAME] = true,
}

local EDITOR_TAGGED_ENTITY_NAMES = {
	[constants.pad_name] = true,
	[constants.ic_name] = true,
}

--------------------------------------------------------------------------------
-- Editor impl
--------------------------------------------------------------------------------

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

---@param surface LuaSurface?
---@return DieShrink.EditorSession?
local function get_editor_session_by_surface(surface)
	if not surface or not surface.valid then
		strace.warn("get_editor_session_by_surface: invalid surface", surface)
		return nil
	end
	local owner_session_id = storage.surface_to_session
		and storage.surface_to_session[surface.index]
	return owner_session_id
		and storage.editor_sessions
		and storage.editor_sessions[owner_session_id]
end

---@param tags Tags?
---@return DieShrink.EditorPadInfo?
local function get_pad_info_from_tags(tags)
	if not tags then return nil end
	if
		tags.pin == nil
		and tags.label == nil
		and tags.i == nil
		and tags.o == nil
	then
		return nil
	end
	return {
		pin = tags.pin,
		label = tags.label,
		i = tags.i,
		o = tags.o,
	}
end

---@param session DieShrink.EditorSession?
---@param pad LuaEntity?
---@param tags Tags?
local function apply_pad_tags(session, pad, tags)
	if
		not session
		or not pad
		or not pad.valid
		or pad.name ~= constants.pad_name
	then
		return
	end
	local initial_info = get_pad_info_from_tags(tags)
	strace.trace(
		"apply_pad_tags",
		session,
		pad,
		pad.unit_number,
		tags,
		initial_info
	)
	if not initial_info then return end
	session:set_pad_info(pad.unit_number, initial_info)
end

---@return {[ID]: DieShrink.EditorSession}
local function get_editor_sessions()
	if not storage.editor_sessions then storage.editor_sessions = {} end
	return storage.editor_sessions
end

---@return {[uint]: ID}
local function get_surface_to_session()
	if not storage.surface_to_session then storage.surface_to_session = {} end
	return storage.surface_to_session
end

---@param surface LuaSurface?
---@return boolean
local function is_editor_surface(surface)
	if not surface or not surface.valid then return false end
	local surface_to_session = storage.surface_to_session
	return surface_to_session and surface_to_session[surface.index] ~= nil
		or false
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
	local ghost_unit_number = entity.unit_number
	local ghost_name = entity.ghost_name
	strace.trace(
		"handle_built_ghost: ghost is",
		entity,
		ghost_name,
		ghost_unit_number
	)
	if ghost_name and ALLOWED_ENTITY_NAMES[ghost_name] then
		local ghost_tags = entity.tags
		local _, revived = entity.silent_revive({ raise_revive = true })
		strace.trace("revived ghost into", revived, "with tags", ghost_tags)
		if revived and ghost_name == constants.pad_name then
			local session = get_editor_session_by_surface(revived.surface)
			apply_pad_tags(session, revived, ghost_tags)
		end
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
---@param force string|integer|LuaForce|nil
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
			nil,
			EDITOR_ENERGY_SOURCE_NAME,
			{ EDITOR_SIZE / 2 + 4, 10 }
		)
	end

	local radar_proto = prototypes.entity[EDITOR_RADAR_NAME]
	if radar_proto then
		ensure_single_editor_entity(surface, force, EDITOR_RADAR_NAME, { 0, 0 })
	end
end

---@param session_id ID
---@return LuaSurface
local function get_or_create_editor_surface(session_id)
	local surface_to_session = get_surface_to_session()

	---@param surface LuaSurface
	---@return LuaSurface
	local function claim_surface(surface)
		surface_to_session[surface.index] = session_id
		return surface
	end

	local hot_surface = storage.editor_hot_surface
	if not hot_surface or not hot_surface.valid then
		hot_surface = game.get_surface(EDITOR_SURFACE_PREFIX .. "hot")
	end
	if not hot_surface or not hot_surface.valid then
		hot_surface = create_editor_surface(EDITOR_SURFACE_PREFIX .. "hot")
	end
	storage.editor_hot_surface = hot_surface
	if surface_to_session[hot_surface.index] == nil then
		return claim_surface(hot_surface)
	end

	while true do
		local next_id = counters.next("die_shrink_editor_surface")
		local surface_name = EDITOR_SURFACE_PREFIX .. tostring(next_id)

		local existing = game.get_surface(surface_name)
		if not existing then
			local new_surface = create_editor_surface(surface_name)
			return claim_surface(new_surface)
		end
	end
end

---@param surface LuaSurface
local function clear_editor_surface(surface)
	for _, entity in ipairs(surface.find_entities()) do
		if entity.valid and entity.type ~= "character" then
			entity.destroy({ raise_destroy = true })
		end
	end
end

---@param surface LuaSurface
---@param session_id ID
local function release_editor_surface(surface, session_id)
	if not surface or not surface.valid then return end

	local surface_to_session = get_surface_to_session()
	if surface_to_session[surface.index] == session_id then
		surface_to_session[surface.index] = nil
	end

	clear_editor_surface(surface)

	local hot_surface = storage.editor_hot_surface
	if not hot_surface or not hot_surface.valid then
		storage.editor_hot_surface = nil
		hot_surface = nil
	end

	if not hot_surface or surface.index ~= hot_surface.index then
		game.delete_surface(surface)
	end
end

---@param session DieShrink.EditorSession
---@param surface LuaSurface
---@param force any
---@return string?
local function capture_editor_blueprint(session, surface, force)
	strace.trace("--- CAPTURE_EDITOR_BLUEPRINT")
	local inv = game.create_inventory(1)
	local bp = inv[1]
	bp.set_stack({ name = "blueprint", count = 1 })
	local entities = bp.create_blueprint({
		surface = surface,
		force = force,
		area = EDITOR_BLUEPRINT_AREA,
	})
	-- Delegate to Things to extract tags for nested ICs.
	remote.call("things", "script_create_blueprint", bp, entities)

	if entities then
		for index, entity in ipairs(entities) do
			if entity and entity.valid then
				if entity.name == constants.pad_name then
					local pad_info = session.pads[entity.unit_number]
					if pad_info then
						strace.trace("Capture: tagging pad", entity.unit_number)
						bp.set_blueprint_entity_tags(index, {
							pin = pad_info.pin,
							label = pad_info.label,
							i = pad_info.i,
							o = pad_info.o,
						})
					end
				end
			end
		end
	end

	local content = nil
	local captured_entities = EMPTY
	if bp.is_blueprint_setup and bp.get_blueprint_entity_count() > 0 then
		captured_entities = bp.get_blueprint_entities() or EMPTY
		content = bp.export_stack()
	end
	inv.destroy()
	strace.trace("Captured blueprint", captured_entities)
	strace.trace("--- CAPTURE_EDITOR_BLUEPRINT DONE")
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
	strace.trace("--- RESTORE_EDITOR_BLUEPRINT")
	local inv = game.create_inventory(1)
	local bp = inv[1]
	bp.set_stack({ name = "blueprint", count = 1 })
	local import_result = bp.import_stack(blueprint)
	if import_result ~= 1 then
		local build_position = get_recentered_build_position(
			bp.get_blueprint_entities()
		) or { 0, 0 }
		remote.call(
			"things",
			"script_prebuild_blueprint",
			bp,
			nil,
			surface,
			{ position = build_position, direction = defines.direction.north },
			defines.build_mode.forced
		)
		local built = bp.build_blueprint({
			surface = surface,
			force = force,
			position = build_position,
			build_mode = defines.build_mode.forced,
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
	strace.trace("--- RESTORE_EDITOR_BLUEPRINT DONE")
end

---@param session_id ID
local function save_editor_session(session_id)
	local editor_sessions = get_editor_sessions()
	---@type DieShrink.EditorSession?
	local session = editor_sessions[session_id]
	if not session then return end

	---@type LuaPlayer?
	local player = session.player
	if not player or not player.valid then return end

	local surface = session.surface
	if not surface or not surface.valid then return end

	local ic = session.ic
	if not ic then return end

	local get_error, thing = remote.call("things", "get", ic.thing_id)
	if not thing then return end

	local force = player.force --[[@as LuaForce]]

	---@type string?
	local blueprint = capture_editor_blueprint(session, surface, force)
	local set_error
	if blueprint then
		local blueprint_content = blueprint --[[@as string]]
		set_error = remote.call(
			"things",
			"set_tag",
			ic.thing_id,
			"blueprint",
			blueprint_content
		)
	else
		local tags = shallow_copy_tags(thing.tags)
		tags.blueprint = nil
		set_error = remote.call("things", "set_tags", ic.thing_id, tags)
	end
end

---@param player LuaPlayer
---@param ic DieShrink.IC
local function open_editor_for_ic(player, ic)
	local _, thing = remote.call("things", "get", ic.thing_id)
	if not thing then return end

	local session = EditorSession:new(player, ic, nil)
	local player_state = get_or_create_player_state(player.index)
	player_state:push_editor_session(session.id)

	local surface = get_or_create_editor_surface(session.id)
	session.surface = surface
	prepare_surface_for_force(surface, player.force --[[@as LuaForce]])
	connect_editor_infra(surface, player.force --[[@as LuaForce]])

	local blueprint = thing.tags and thing.tags.blueprint
	if type(blueprint) == "string" and blueprint ~= "" then
		local blueprint_content = blueprint --[[@as string]]
		local player_force = player.force --[[@as LuaForce]]
		restore_editor_blueprint(surface, player_force, blueprint_content)
	end

	player.set_controller({
		type = defines.controllers.remote,
		surface = surface,
		position = { 0, 0 },
	})
	if player.zoom < EDITOR_ENTRY_MIN_ZOOM then
		player.zoom = EDITOR_ENTRY_MIN_ZOOM
	end

	event.raise("dieshrink.editor_session_opened", session)
end

event.bind(defines.events.on_player_controller_changed, function(ev)
	local session = get_current_editor_session(ev.player_index)
	if not session then return end

	local player = game.get_player(ev.player_index)
	if not player then return end
	if player.controller_type ~= defines.controllers.remote then
		close_current_editor_session(ev.player_index)
	end
end)

event.bind(defines.events.on_player_changed_surface, function(ev)
	local session = get_current_editor_session(ev.player_index)
	if not session then return end

	local player = game.get_player(ev.player_index)
	if not player then return end
	if player.surface ~= session.surface then
		close_current_editor_session(ev.player_index)
	end
end)

event.bind(defines.events.on_pre_player_left_game, function(ev)
	while get_current_editor_session(ev.player_index) do
		close_current_editor_session(ev.player_index)
	end
end)

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
---@param tags Tags?
---@param player_index uint?
local function handle_editor_surface_build(entity, tags, player_index)
	if
		not entity
		or not entity.valid
		or not is_editor_surface(entity.surface)
	then
		return
	end

	strace.trace("editor_surface_build", player_index, entity, tags)
	if tags and EDITOR_TAGGED_ENTITY_NAMES[entity.name] then
		local session = get_editor_session_by_surface(entity.surface)
		if entity.name == constants.pad_name then
			apply_pad_tags(session, entity, tags)
		end
	end

	if entity.name ~= "entity-ghost" then return end

	local player = player_index and game.get_player(player_index) or nil
	handle_built_ghost(entity, player)
end

event.bind(
	defines.events.on_built_entity,
	function(ev) handle_editor_surface_build(ev.entity, ev.tags, ev.player_index) end
)

event.bind(
	defines.events.script_raised_built,
	function(ev) handle_editor_surface_build(ev.entity, ev.tags, nil) end
)

event.bind(
	defines.events.script_raised_revive,
	function(ev) handle_editor_surface_build(ev.entity, ev.tags, nil) end
)

--------------------------------------------------------------------------------
-- Editor session
--------------------------------------------------------------------------------

---@class DieShrink.EditorPadInfo
---@field unit_number UnitNumber
---@field pin? integer
---@field label? string
---@field i? boolean
---@field o? boolean

---@class DieShrink.EditorSession
---@field id ID Session identifier.
---@field player LuaPlayer The player owning this editor session.
---@field ic DieShrink.IC The IC being edited in this session.
---@field surface LuaSurface The editor surface for this session.
---@field pads {[UnitNumber]: DieShrink.EditorPadInfo} The pads currently in this editor session.
local EditorSession = class("DieShrink.EditorSession")
_G.EditorSession = EditorSession

---@param player LuaPlayer
---@param ic DieShrink.IC
---@param surface LuaSurface?
function EditorSession:new(player, ic, surface)
	---@type DieShrink.EditorSession
	local session = setmetatable({
		id = counters.next("editor_session"),
		player = player,
		ic = ic,
		surface = surface,
		pads = {},
	}, self)
	storage.editor_sessions = storage.editor_sessions or {}
	storage.editor_sessions[session.id] = session
	return session
end

---@param unit_number UnitNumber
---@param initial_info? fun(): DieShrink.EditorPadInfo
function EditorSession:get_or_create_pad_info(unit_number, initial_info)
	local pad_info = self.pads[unit_number]
	if not pad_info then
		pad_info = initial_info and initial_info() or {}
		pad_info.unit_number = unit_number
		self.pads[unit_number] = pad_info
	end
	return pad_info
end

---@param unit_number UnitNumber
---@param info DieShrink.EditorPadInfo
function EditorSession:set_pad_info(unit_number, info)
	self.pads[unit_number] = info
	event.raise("dieshrink.editor_session_pad_changed", self, unit_number)
end

function EditorSession:get_pad_info(unit_number)
	return self.pads[unit_number] or EMPTY
end

function EditorSession:set_pad_pin(unit_number, pin)
	self:get_or_create_pad_info(unit_number).pin = pin
	event.raise("dieshrink.editor_session_pad_changed", self, unit_number)
end

function EditorSession:get_pad_pin(unit_number)
	return self:get_pad_info(unit_number).pin
end

function EditorSession:set_pad_label(unit_number, label)
	self:get_or_create_pad_info(unit_number).label = label
	event.raise("dieshrink.editor_session_pad_changed", self, unit_number)
end

function EditorSession:set_pad_i(unit_number, is_in)
	self:get_or_create_pad_info(unit_number).i = is_in
	event.raise("dieshrink.editor_session_pad_changed", self, unit_number)
end

function EditorSession:set_pad_o(unit_number, is_out)
	self:get_or_create_pad_info(unit_number).o = is_out
	event.raise("dieshrink.editor_session_pad_changed", self, unit_number)
end

function EditorSession:destroy()
	if storage.editor_sessions then storage.editor_sessions[self.id] = nil end
end

---@param player_index PlayerIndex
---@param ic DieShrink.IC
function _G.open_editor_session(player_index, ic)
	local player = game.get_player(player_index)
	if not player or not player.valid then return end
	open_editor_for_ic(player, ic)
end

---@param session_id ID
---@return DieShrink.EditorSession?
function _G.get_editor_session(session_id)
	local editor_sessions = get_editor_sessions()
	return editor_sessions and editor_sessions[session_id] or nil
end

---@param surface_index SurfaceIndex
function _G.get_editor_session_for_surface(surface_index)
	local surface_to_session = get_surface_to_session()
	local session_id = surface_to_session[surface_index]
	if not session_id then return nil end
	return get_editor_session(session_id)
end

---@param player_index PlayerIndex
---@return DieShrink.EditorSession?
function _G.get_current_editor_session(player_index)
	local player_state = get_player_state(player_index)
	if not player_state then return nil end
	return player_state:get_current_editor_session()
end

---@param session_id ID
function _G.close_editor_session(session_id)
	local editor_sessions = storage.editor_sessions
	if not editor_sessions or not editor_sessions[session_id] then return end
	local session = editor_sessions[session_id]

	local player_index = session.player.index
	local player_state = get_or_create_player_state(player_index)
	local top_session_id = player_state:get_current_editor_session_id()
	if top_session_id ~= session_id then
		strace.warn("close_editor_session called for non-top session", {
			session_id = session_id,
			top_session_id = top_session_id,
			player_index = player_index,
		})
		return
	end

	player_state:pop_editor_session()

	save_editor_session(session_id)
	release_editor_surface(session.surface, session_id)
	session:destroy()
	event.raise("dieshrink.editor_session_closed", session)

	---@type LuaPlayer?
	local player = session.player
	if (not player) or not player.valid then
		player = game.get_player(player_index)
	end
	if not player or not player.valid then return end

	local next_session = player_state:get_current_editor_session()
	if next_session then
		if next_session and next_session.surface and next_session.surface.valid then
			player.set_controller({
				type = defines.controllers.remote,
				surface = next_session.surface,
				position = { 0, 0 },
			})
			if player.zoom < EDITOR_ENTRY_MIN_ZOOM then
				player.zoom = EDITOR_ENTRY_MIN_ZOOM
			end
			event.raise("dieshrink.editor_session_opened", next_session)
			return
		end
	end

	if player.controller_type == defines.controllers.remote then
		player.exit_remote_view()
	end
end

---@param player_index PlayerIndex
function _G.close_current_editor_session(player_index)
	local session = get_current_editor_session(player_index)
	if not session then return end
	close_editor_session(session.id)
end
