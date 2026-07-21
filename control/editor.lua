--------------------------------------------------------------------------------
-- Circuit editor
--------------------------------------------------------------------------------

local class = require("lib.core.class").class
local event = require("lib.core.event")
local constants = require("lib.constants")
local strace = require("lib.core.strace")
local counters = require("lib.core.counters")
local tlib = require("lib.core.table")
local scheduler = require("lib.core.scheduler")
local pos_lib = require("lib.core.math.pos")
---@diagnostic disable-next-line: unresolved-require
local things_client = require("__0-things__.client.client") --[[@as things.client]]

local get_tags = things_client.tags_v1.get_tags

local rcall = remote.call --[[@as fun(iface: string, method: string, ...: Any): Any ]]
local EMPTY = tlib.EMPTY
local pos_get = pos_lib.pos_get

local EDITOR_SURFACE_PREFIX = "die-shrink-editor-s-"
local EDITOR_SIZE = 32
local EDITOR_GENERATION_PADDING = 2
local EDITOR_CHUNK_RADIUS =
	math.max(2, math.ceil((EDITOR_SIZE / 2 + EDITOR_GENERATION_PADDING) / 32))
local EDITOR_ENTRY_MIN_ZOOM = 1
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
	["display-panel"] = true,
	[constants.pad_name] = true,
	[constants.ic_name] = true,
	[constants.pin_name] = true,
	[constants.option_name] = true,
}

local EDITOR_SYSTEM_ENTITY_NAMES = {
	[EDITOR_ENERGY_SOURCE_NAME] = true,
	[EDITOR_RADAR_NAME] = true,
}

--------------------------------------------------------------------------------
-- Editor impl
--------------------------------------------------------------------------------

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

---@param surface LuaSurface?
---@return DieShrink.EditorSession?
local function get_editor_session_by_surface(surface)
	if not surface or not surface.valid then return nil end
	local owner_session_id = storage.surface_to_session
		and storage.surface_to_session[surface.index]
	return owner_session_id
		and storage.editor_sessions
		and storage.editor_sessions[owner_session_id]
end

---@param entity LuaEntity
---@param thing_id ThingID
---@return string?
local function assign_unique_option_key(entity, thing_id)
	local used = {}
	for _, option_entity in
		ipairs(entity.surface.find_entities_filtered({
			name = constants.option_name,
		}))
	do
		local _, option_thing = rcall("things", "get", option_entity)
		---@cast option_thing things.ThingSummary
		if option_thing and option_thing.id ~= thing_id then
			local key = (option_thing.tags or EMPTY)["key"]
			if key then used[tostring(key)] = true end
		end
	end

	local next_key = math.random(1, 1000000)
	while used[tostring(next_key)] do
		next_key = math.random(1, 1000000)
	end

	local next_key_str = tostring(next_key)
	strace.trace(
		"assign_unique_option_key: assigning key",
		next_key_str,
		"to thing",
		thing_id
	)
	rcall("things-tags-v1", "set_tag", thing_id, "key", next_key_str)
	return next_key_str
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
		speed = 4,
	})
end

---@param entity LuaEntity
---@param player LuaPlayer?
---@param session DieShrink.EditorSession
local function handle_built_ghost(entity, player, session)
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
		if revived then
			strace.trace("revived ghost into", revived, "with tags", ghost_tags)
		end
		return
	end
	notify_not_allowed(ghost_name or "unknown", player, entity.position)
	entity.destroy()
end

---@param session DieShrink.EditorSession
---@return LuaSurface
local function create_editor_surface(session)
	local next_id = counters.next("die_shrink_editor_surface")
	local surface_name = EDITOR_SURFACE_PREFIX .. tostring(next_id)
	local surface_to_session = get_surface_to_session()
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
	surface_to_session[surface.index] = session.id
	session.surface = surface
	for _, force in pairs(game.forces) do
		force.set_surface_hidden(surface, true)
	end
	surface.always_day = true
	surface.daytime = 0.5
	surface.freeze_daytime = true
	surface.show_clouds = false
	surface.request_to_generate_chunks({ 0, 0 }, EDITOR_CHUNK_RADIUS)
	surface.force_generate_chunk_requests()
	surface.create_global_electric_network()

	-- Deco and tiles
	surface.destroy_decoratives({})
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
		local tpx, tpy = pos_get(pos)
		if math.abs(tpx) > EDITOR_SIZE / 2 or math.abs(tpy) > EDITOR_SIZE / 2 then
			tiles[#tiles + 1] = { name = "out-of-map", position = pos }
		else
			tiles[#tiles + 1] = { name = tile_name, position = pos }
		end
	end
	surface.set_tiles(tiles)

	-- Initial chart
	-- XXX: TYPES: potential FMTK bug, this can't actually be nil
	---@diagnostic disable-next-line: need-check-nil
	session.player.force.chart(surface, EDITOR_CHART_AREA)

	-- Energy source
	local eei = surface.create_entity({
		name = EDITOR_ENERGY_SOURCE_NAME,
		position = { EDITOR_SIZE / 2 + 4, 10 },
		force = session.player.force,
	})
	if not eei then
		strace.error("Failed to create editor energy source entity")
	end

	-- Hidden Radar
	local radar = surface.create_entity({
		name = EDITOR_RADAR_NAME,
		position = { 0, 0 },
		force = session.player.force,
	})
	if not radar then
		strace.error("Failed to create editor radar entity")
	else
		radar.operable = false
		radar.destructible = false
	end

	return surface
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
	game.delete_surface(surface)
end

---@param session DieShrink.EditorSession
---@param surface LuaSurface
---@param force any
---@return string?
local function capture_editor_blueprint(session, surface, force)
	strace.trace("--- CAPTURE_EDITOR_BLUEPRINT")
	local inv = game.create_inventory(1)
	local bp = inv[1]

	-- XXX: TYPES: Emmy or fmtk bug
	---@diagnostic disable-next-line: param-type-mismatch
	bp.set_stack({ name = "blueprint", count = 1 })
	-- Cooperative extract blueprint
	rcall("cooperative-blueprinting-v1", "create_blueprint", bp, {
		surface = surface,
		force = force,
		area = EDITOR_BLUEPRINT_AREA,
	})

	local content = nil
	-- TODO: this is only used for debug dump, remove.
	local captured_entities = EMPTY
	if bp.is_blueprint_setup and bp.get_blueprint_entity_count() > 0 then
		captured_entities = bp.get_blueprint_entities() or EMPTY
		content = bp.export_stack()
	end
	inv.destroy()
	strace.trace(
		"Captured blueprint",
		function()
			return serpent.line(captured_entities, { maxlevel = 10, nocode = true })
		end
	)
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

			local px, py = pos_get(bp_entity.position)
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

---@param session DieShrink.EditorSession
---@param surface LuaSurface
---@param force LuaForce
---@param blueprint string
local function restore_editor_blueprint(session, surface, force, blueprint)
	strace.trace("--- RESTORE_EDITOR_BLUEPRINT")
	strace.trace(
		"Restoring blueprint",
		surface.name,
		surface.valid,
		force,
		blueprint
	)

	local inv = game.create_inventory(1)
	local bp = inv[1]
	-- XXX: TYPES: Emmy or fmtk bug
	---@diagnostic disable-next-line: param-type-mismatch
	bp.set_stack({ name = "blueprint", count = 1 })
	local import_result = bp.import_stack(blueprint)
	if import_result ~= 1 then
		local entities = bp.get_blueprint_entities()
		strace.trace("Restoring blueprint entities", entities)
		local build_position = get_recentered_build_position(entities) or { 0, 0 }
		strace.trace("Build position", build_position)
		local build_args = {
			surface = surface,
			force = force,
			position = build_position,
			build_mode = defines.build_mode.forced,
			skip_fog_of_war = true,
		}
		strace.trace("cooperative build_blueprint with build args", build_args)
		local built = remote.call(
			"cooperative-blueprinting-v1",
			"build_blueprint",
			bp,
			build_args
		) --[[@as LuaEntity[]?]]
		if not built then
			strace.warn("Failed to build blueprint on editor surface", surface.name)
			return
		end
		strace.trace("Built entities", built)

		for _, entity in pairs(built) do
			if entity.name == "entity-ghost" then
				handle_built_ghost(entity, nil, session)
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

	local blueprint = capture_editor_blueprint(session, surface, force)

	if blueprint then
		strace.trace("Saving ic tags", ic.thing_id, "with blueprint", blueprint)
		remote.call("things", "set_tag", ic.thing_id, "blueprint", blueprint)
	else
		remote.call("things", "set_tag", ic.thing_id, "blueprint", nil)
	end
end

scheduler.register_handler("load_session", function(task)
	-- Paste blueprint into editor
	-- XXX: TYPES: EmmyLua doesnt understand the table-unpack here???
	---@diagnostic disable-next-line: missing-parameter
	restore_editor_blueprint(table.unpack(task.data))
end)

---@param player LuaPlayer
---@param ic DieShrink.IC
local function open_editor_for_ic(player, ic)
	local _, thing = remote.call("things", "get", ic.thing_id)
	if not thing then return end

	local session = EditorSession:new(player, ic, nil)
	local player_state = get_or_create_player_state(player.index)
	player_state:push_editor_session(session.id)

	local surface = create_editor_surface(session)

	local blueprint = thing.tags and thing.tags.blueprint
	if type(blueprint) == "string" and blueprint ~= "" then
		local blueprint_content = blueprint --[[@as string]]
		local player_force = player.force --[[@as LuaForce]]
		scheduler.after(
			1,
			"load_session",
			{ session, surface, player_force, blueprint_content }
		)
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
	local session = get_editor_session_by_surface(entity.surface)
	if not session then return end

	if entity.name ~= "entity-ghost" then return end

	local player = player_index and game.get_player(player_index) or nil
	handle_built_ghost(entity, player, session)
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

---@class (partial) DieShrink.LabeledEntityInfo
---@field entity LuaEntity
---@field type string "pad"
---@field ro? LuaRenderObject

---@class DieShrink.EditorSession
---@field id ID Session identifier.
---@field player LuaPlayer The player owning this editor session.
---@field ic DieShrink.IC The IC being edited in this session.
---@field surface LuaSurface The editor surface for this session.
---@field labels {[int64]: DieShrink.LabeledEntityInfo} The entities with labels in this editor session.
EditorSession = class("DieShrink.EditorSession")

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
		labels = {},
	}, self)
	storage.editor_sessions = storage.editor_sessions or {}
	storage.editor_sessions[session.id] = session
	return session
end

---@param thing things.ThingSummary
---@param type "pad" Currently only supports pads, but could be extended to other entity types with labels in the future.
function EditorSession:create_label(thing, type)
	if not thing then return end
	if self.labels[thing.id] then return end
	local label_info = {
		thing_id = thing.id,
		type = type,
	}
	self.labels[thing.id] = label_info
	self:update_label(thing)
	return label_info
end

function EditorSession:destroy_label(label)
	if not label then return end
	local ro = label.ro
	if ro and ro.valid then ro.destroy() end
	self.labels[label.thing_id] = nil
end

---@param thing things.ThingShortSummary
function EditorSession:update_label(thing)
	local label = self.labels[thing.id]
	if type(label) ~= "table" then return end

	local entity = thing.entity
	if not entity or not entity.valid then
		self:destroy_label(label)
		return
	end

	local info = get_tags(thing.id) or EMPTY
	local label_text = info.pin and tostring(info.pin) or "[color=red]!![/color]"
	if info.label then
		label_text = label_text .. ":  " .. tostring(info.label)
	end

	local ro = label.ro
		or rendering.draw_text({
			text = "",
			surface = self.surface,
			target = { entity = entity, offset = { 0, -0.8 } },
			color = { r = 1, g = 1, b = 0 },
			alignment = "center",
			use_rich_text = true,
		})
	---@diagnostic disable-next-line: inject-field
	label.ro = ro
	ro.text = label_text
end

function EditorSession:destroy_labels()
	for _, label in pairs(self.labels) do
		self:destroy_label(label)
	end
end

function EditorSession:set_pad_pin(thing_id, pin)
	rcall("things-tags-v1", "set_tag", thing_id, "pin", pin)
end

function EditorSession:get_pad_pin(thing_id)
	local _, pin = rcall("things-tags-v1", "get_tag", thing_id, "pin")
	return pin
end

function EditorSession:set_pad_label(thing_id, label)
	rcall("things-tags-v1", "set_tag", thing_id, "label", label)
end

function EditorSession:get_pad_label(thing_id)
	local _, label = rcall("things-tags-v1", "get_tag", thing_id, "label")
	return label
end

function EditorSession:set_option_definition(thing_id, definition)
	rcall("things-tags-v1", "set_tags", thing_id, definition)
end

function EditorSession:get_option_definition(thing_id)
	local _, definition = rcall("things-tags-v1", "get_tags", thing_id)
	return definition
end

function EditorSession:destroy()
	self:destroy_labels()
	if storage.editor_sessions then storage.editor_sessions[self.id] = nil end
end

event.bind(
	"dieshrink.editor_session_pad_changed",
	---@param sess DieShrink.EditorSession
	---@param thing things.ThingShortSummary
	function(sess, _, _, thing) sess:update_label(thing) end
)

event.bind(
	"die-shrink-on_editor_thing_initialized",
	---@param ev things.EventData.on_initialized
	function(ev)
		local entity = ev.entity
		if not entity or not entity.valid then
			strace.warn("on_editor_thing_initialized called with invalid entity", ev)
			return
		end

		local session = get_editor_session_by_surface(entity.surface)
		if not session then
			strace.warn(
				"on_editor_thing_initialized called for entity on non-editor surface",
				entity.surface.name
			)
			return
		end

		strace.trace("die-shrink-on_editor_thing_initialized", ev)
		if ev.thing_name == constants.pad_name then
			session:create_label(ev, "pad")
		elseif ev.thing_name == constants.option_name then
			-- Assign a unique option key to new option entities.
			if not ev.from_blueprint then
				if (not ev.tags) or not ev.tags.key then
					assign_unique_option_key(entity, ev.id)
				end
			end
		end
	end
)

event.bind(
	"die-shrink-on_editor_thing_tags_changed",
	---@param ev things.EventData.on_tags_changed
	function(ev)
		local thing = ev.thing
		local entity = thing.entity
		if not entity or not entity.valid then return end
		local session = get_editor_session_by_surface(entity.surface)
		if not session then
			strace.warn(
				"on_editor_thing_tags_changed called for entity on non-editor surface",
				entity.surface.name
			)
			return
		end
		if thing.name == constants.pad_name then
			event.raise(
				"dieshrink.editor_session_pad_changed",
				session,
				thing.id,
				ev.new_tags,
				thing
			)
		elseif thing.name == constants.option_name then
			event.raise(
				"dieshrink.editor_session_option_changed",
				session,
				thing.id,
				ev.new_tags,
				thing
			)
		end
	end
)

--------------------------------------------------------------------------------
-- Api
--------------------------------------------------------------------------------

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
	event.raise("dieshrink.editor_session_closed", session, true)

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
