--------------------------------------------------------------------------------
-- LINKER
-- Takes a CompilerResult and produces real world entities and script
-- wire connections between them.
-- Returns a LinkerResult that can be later used to unlink.
--------------------------------------------------------------------------------

local tlib = require("lib.core.table")
local pos_lib = require("lib.core.math.pos")

local EMPTY = tlib.EMPTY
local INVALID_SENTINEL = { valid = false }

local pos_add = pos_lib.pos_add

local lib = {}

local RED = defines.wire_connector_id.circuit_red
local GREEN = defines.wire_connector_id.circuit_green

---@param from_entity LuaEntity
---@param from_connector defines.wire_connector_id
---@param to_entity LuaEntity
---@param to_connector defines.wire_connector_id
---@return boolean
local function connect_entities(
	from_entity,
	from_connector,
	to_entity,
	to_connector
)
	if not from_entity.valid or not to_entity.valid then return false end

	local from_wc = from_entity.get_wire_connector(from_connector, true)
	local to_wc = to_entity.get_wire_connector(to_connector, true)
	if not from_wc or not to_wc then return false end
	return from_wc.connect_to(to_wc, false, defines.wire_origin.script)
end

---@param from_entity LuaEntity
---@param from_connector defines.wire_connector_id
---@param to_entity LuaEntity
---@param to_connector defines.wire_connector_id
local function disconnect_entities(
	from_entity,
	from_connector,
	to_entity,
	to_connector
)
	if not from_entity.valid or not to_entity.valid then return end

	local from_wc = from_entity.get_wire_connector(from_connector, true)
	local to_wc = to_entity.get_wire_connector(to_connector, true)
	if not from_wc or not to_wc then return end
	from_wc.disconnect_from(to_wc, defines.wire_origin.script)
end

---@class DieShrink.LinkerResult
---@field entities LuaEntity[] Real world entities created by the linker.
---@field pin_wires [LuaEntity,defines.wire_connector_id,LuaEntity,defines.wire_connector_id][] List of wires created by the linker for the IC's pins.

---Create entities and wire connections described by `compiled`.
---@param compiled DieShrink.CompilerResult
---@param surface LuaSurface
---@param force LuaForce
---@param position MapPosition
---@param pin_entities {[uint]: LuaEntity} Mapping of external IC pin number to the real world entity representing that pin's connection point.
---@return DieShrink.LinkerResult
function lib.link(compiled, surface, force, position, pin_entities)
	local result_entities = {}
	local result_pin_wires = {}

	---@type DieShrink.LinkerResult
	local link_result = {
		entities = result_entities,
		pin_wires = result_pin_wires,
	}

	if not compiled or not surface or not force or not position then
		return link_result
	end

	-- 1) Create entities from compiler output.
	for _, create_param in ipairs(compiled.entities or EMPTY) do
		-- Params
		local orig_pos = create_param.position
		pos_add(orig_pos, 1, position)
		create_param.force = force
		create_param.raise_built = true
		create_param.create_build_effect_smoke = false

		local entity = surface.create_entity(create_param) or INVALID_SENTINEL
		result_entities[#result_entities + 1] = entity

		create_param.position = orig_pos
		create_param.force = nil
		create_param.raise_built = nil
		create_param.create_build_effect_smoke = nil
	end

	-- 2) Restore internal compiler wires using script origin.
	for _, wire in ipairs(compiled.wires or EMPTY) do
		local a_idx = wire[1]
		local a_connector = wire[2]
		local b_idx = wire[3]
		local b_connector = wire[4]
		local a_entity = result_entities[a_idx]
		local b_entity = result_entities[b_idx]
		connect_entities(a_entity, a_connector, b_entity, b_connector)
	end

	-- 3) Connect external pins to compiled pad connectors.
	for pin_number, connector_indices in pairs(compiled.pad_map or EMPTY) do
		local pin_entity = pin_entities and pin_entities[pin_number]
		if pin_entity and pin_entity.valid then
			for _, connector_index in ipairs(connector_indices) do
				local pad_entity = result_entities[connector_index]
				if pad_entity and pad_entity.valid then
					if connect_entities(pin_entity, RED, pad_entity, RED) then
						result_pin_wires[#result_pin_wires + 1] = {
							pin_entity,
							RED,
							pad_entity,
							RED,
						}
					end
					if connect_entities(pin_entity, GREEN, pad_entity, GREEN) then
						result_pin_wires[#result_pin_wires + 1] = {
							pin_entity,
							GREEN,
							pad_entity,
							GREEN,
						}
					end
				end
			end
		end
	end

	return link_result
end

---Disconnect pin wire connections previously created by `link`.
---@param link_result DieShrink.LinkerResult
function lib.disconnect(link_result)
	if not link_result or not link_result.pin_wires then return end
	for _, wire in ipairs(link_result.pin_wires) do
		disconnect_entities(wire[1], wire[2], wire[3], wire[4])
	end
end

---Reconnect pin wire connections previously created by `link`.
---@param link_result DieShrink.LinkerResult
function lib.reconnect(link_result)
	if not link_result or not link_result.pin_wires then return end
	for _, wire in ipairs(link_result.pin_wires) do
		connect_entities(wire[1], wire[2], wire[3], wire[4])
	end
end

---Destroy entities previously created by `link`. The link result is now
---unusable and you must run `link` again if you wish to recreate the circuit.
---@param link_result DieShrink.LinkerResult
function lib.unlink(link_result)
	if not link_result then return end
	if not link_result.entities then return end
	for _, entity in pairs(link_result.entities) do
		if entity and entity.valid then entity.destroy() end
	end
end

return lib
