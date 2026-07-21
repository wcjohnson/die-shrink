--------------------------------------------------------------------------------
-- CIRCUIT COMPILER
--------------------------------------------------------------------------------

local constants = require("lib.constants")
local tlib = require("lib.core.table")
local strace = require("lib.core.strace")
local option_lib = require("control.option")

local pairs = pairs
local next = next
local type = type
local min = math.min
local max = math.max
local floor = math.floor
local tconcat = table.concat
local sformat = string.format
local tostring = tostring
local EMPTY = tlib.EMPTY

local lib = {}

local COMBINATOR_ENTITY_MAP = {
	["constant-combinator"] = constants.mod_prefix .. "-constant-combinator",
	["arithmetic-combinator"] = constants.mod_prefix .. "-arithmetic-combinator",
	["decider-combinator"] = constants.mod_prefix .. "-decider-combinator",
	["selector-combinator"] = constants.mod_prefix .. "-selector-combinator",
}

local PAD_CONNECTOR_NAME = constants.mod_prefix .. "-pad-connector"

local POWER_CONSUMER_NAME = constants.mod_prefix .. "-power-consumer"

---Given the blueprint tags of a pin, return the blueprint entity index of
---the parent processor within the pin's blueprint.
---@param pin_tags Tags The tags of a pin entity within a blueprint.
---@return uint? ic_index The blueprint entity index of the parent processor, or nil if it can't be determined.
---@return uint? pin_number Pin number within parent IC.
local function get_pin_info_from_tags(pin_tags)
	local _, _, tags, parent_index =
		remote.call("things-metadata-v1", "decode_blueprint_tags", pin_tags)
	return parent_index, tags and tags.n --[[@as uint?]]
end

---@param ic_tags Tags?
---@return string? blueprint_string
---@return DieShrink.OptionChoices? option_choices
local function get_ic_info_from_tags(ic_tags)
	if not ic_tags then return nil end
	local _, _, tags =
		remote.call("things-metadata-v1", "decode_blueprint_tags", ic_tags)
	if not tags then return nil end
	local bp_string = tags.blueprint --[[@as string?]]
	local option_choices = tags.option --[[@as DieShrink.OptionChoices?]]
	return bp_string, option_choices
end

---@class DieShrink.CompilerResult
---@field entities LuaSurface.create_entity_param[]
---@field wires [uint,defines.wire_connector_id,uint,defines.wire_connector_id][] List of wires between entities that should be restored when building.
---@field labels {[uint]: string} Mapping of pin index to label text
---@field pad_map {[uint]: uint[]} Mapping of external IC pin number to corresponding pad connector indices within `entities`.
---@field options {[string]: [DieShrink.OptionDefinition, uint]} List of option definitions available inside the IC along with pointers to the constant combinators representing them in `entities`.

---@return DieShrink.CompilerResult
local function create_empty_result()
	return {
		entities = {},
		wires = {},
		labels = {},
		pad_map = {},
		options = {},
	}
end

---@param pos MapPosition
---@return string
local function get_option_key_from_position(pos)
	local x = pos.x or pos[1] or 0
	local y = pos.y or pos[2] or 0
	return sformat("%.2f,%.2f", x, y)
end

---@param option_def DieShrink.OptionDefinition?
---@param pos MapPosition
---@return string key
local function get_option_key(option_def, pos)
	local option_id = option_def and option_def.key
	if option_id then return tostring(option_id) end
	return get_option_key_from_position(pos)
end

---@param wires [uint, defines.wire_connector_id, uint, defines.wire_connector_id][]
---@param dedupe {[string]: boolean}
---@param a uint
---@param a_connector defines.wire_connector_id
---@param b uint
---@param b_connector defines.wire_connector_id
local function add_wire(wires, dedupe, a, a_connector, b, b_connector)
	if not a or not b then return end
	if a == b and a_connector == b_connector then return end

	local left = min(a, b)
	local right = max(a, b)
	local left_connector
	local right_connector
	if a == b then
		---@diagnostic disable-next-line
		if a_connector <= b_connector then
			left_connector = a_connector
			right_connector = b_connector
		else
			left_connector = b_connector
			right_connector = a_connector
		end
	elseif a == left then
		left_connector = a_connector
		right_connector = b_connector
	else
		left_connector = b_connector
		right_connector = a_connector
	end
	local proposed_wire = { left, left_connector, right, right_connector }
	local key = tconcat(proposed_wire, ":")
	if dedupe[key] then return false end
	dedupe[key] = true
	wires[#wires + 1] = proposed_wire
	return true
end

---@param pad_map {[uint]: uint[]}
---@param pad_number uint?
---@param connector_index uint?
local function add_pad_mapping(pad_map, pad_number, connector_index)
	if not pad_number or not connector_index then return end
	local mapped = pad_map[pad_number]
	if not mapped then
		mapped = {}
		pad_map[pad_number] = mapped
	end
	mapped[#mapped + 1] = connector_index
end

---@param labels {[uint]: string}
---@param pin_number uint?
---@param label string?
local function add_pin_label(labels, pin_number, label)
	if not pin_number or not label or label == "" then return end
	local existing = labels[pin_number]
	if not existing or existing == "" then
		labels[pin_number] = label
	else
		labels[pin_number] = existing .. " / " .. label
	end
end

---Compile a circuit from its editor blueprint.
---@param bp_entities string|BlueprintEntity[]
---@param initial_options? DieShrink.OptionChoices
---@param recursion_level? uint
---@param get_next_position? fun(): MapPosition
---@return DieShrink.CompilerResult? result The compiled circuit, or nil if compilation failed.
local function compile(
	bp_entities,
	initial_options,
	recursion_level,
	get_next_position
)
	local result = create_empty_result()
	initial_options = initial_options or tlib.empty

	-- Compile string if needed
	if type(bp_entities) == "string" then
		strace.trace("Compiling from blueprint string")
		local inv = game.create_inventory(1)
		local bp = inv[1]
		-- XXX: TYPES: Emmy or fmtk bug
		---@diagnostic disable-next-line: param-type-mismatch
		bp.set_stack({ name = "blueprint", count = 1 })
		local import_result = bp.import_stack(bp_entities)
		if import_result == 1 then
			strace.error("Failed to import blueprint string for compilation")
			inv.destroy()
			return nil
		end
		bp_entities = bp.get_blueprint_entities() or {}
		inv.destroy()
	end
	---@cast bp_entities BlueprintEntity[]

	strace.trace(
		"Compiling from",
		#bp_entities,
		"blueprint entities with options",
		initial_options
	)
	local level = recursion_level or 0
	if not get_next_position then
		local min_x = -0.45
		local min_y = -0.45
		local max_x = 0.45
		local max_y = 0.45
		local step = 0.03
		local span_x = max_x - min_x
		local span_y = max_y - min_y
		local columns = math.max(1, math.floor(span_x / step + 0.5) + 1)
		local rows = math.max(1, math.floor(span_y / step + 0.5) + 1)
		local ix = 0
		local iy = 0

		get_next_position = function()
			local pos = {
				min_x + ix * step,
				min_y + iy * step,
			}
			ix = ix + 1
			if ix >= columns then
				ix = 0
				iy = iy + 1
				if iy >= rows then iy = 0 end
			end
			return pos
		end
	end

	local result_entities = result.entities

	---Map from bp indices to compiled indices
	---@type {[uint]: uint}
	local bp_to_compiled = {}
	---Embedded ICs. (bp index of ic) -> (pin number -> bp index of pin)
	---@type {[uint]: {[uint]: uint}}
	local bp_ics = {}
	---Pins (bp index of pin) -> [bp index of IC, pin number]
	---@type {[uint]: [uint, uint]}
	local bp_pins = {}

	-- Create the power-consuming entity for the compiled circuit
	result_entities[#result_entities + 1] = {
		name = POWER_CONSUMER_NAME,
		position = { 0, 0 },
	}

	-- PASS 1: CLASSIFICATION
	for bp_index, bp_entity in pairs(bp_entities) do
		local entity_name = bp_entity.name
		local combinator_name = COMBINATOR_ENTITY_MAP[entity_name]

		if combinator_name then
			local combinator_index = #result_entities + 1
			local param = {
				name = combinator_name,
				position = get_next_position(),
				direction = bp_entity.direction,
				control_behavior = bp_entity.control_behavior,
			}
			strace.trace(
				"Compiled index",
				combinator_index,
				"is a",
				combinator_name,
				"coming from bp_index",
				bp_index
			)
			result_entities[combinator_index] = param --[[@as LuaSurface.create_entity_param]]
			bp_to_compiled[bp_index] = combinator_index
		elseif entity_name == constants.pad_name then
			-- Create and map pad connector.
			local _, _, tags = remote.call(
				"things-metadata-v1",
				"decode_blueprint_tags",
				bp_entity.tags
			)
			local pin_number = tags and tags.pin --[[@as uint?]]
			if pin_number then
				local connector_index = #result_entities + 1
				result_entities[connector_index] = {
					name = PAD_CONNECTOR_NAME,
					position = get_next_position(),
					direction = bp_entity.direction,
				} --[[@as LuaSurface.create_entity_param]]
				bp_to_compiled[bp_index] = connector_index
				add_pad_mapping(result.pad_map, pin_number, connector_index)
				strace.trace(
					"Index",
					connector_index,
					"is a connector pad for pin",
					pin_number,
					"bp_index",
					bp_index
				)
				add_pin_label(
					result.labels,
					pin_number,
					tags and tags.label and tostring(tags.label) or nil
				)
			end
		elseif entity_name == constants.option_name then
			local _, _, option_def = remote.call(
				"things-metadata-v1",
				"decode_blueprint_tags",
				bp_entity.tags
			)
			if option_def and option_def.type then
				local combinator_index = #result_entities + 1
				local position = get_next_position()
				local option_key = get_option_key(option_def, bp_entity.position)
				option_def.key = option_key
				local option_choice = initial_options[option_key]
				local param = {
					name = COMBINATOR_ENTITY_MAP["constant-combinator"],
					position = position,
					direction = bp_entity.direction,
					control_behavior = option_lib.generate_option_control_behavior(
						option_def,
						option_choice
					),
				}
				result_entities[combinator_index] = param --[[@as LuaSurface.create_entity_param]]
				bp_to_compiled[bp_index] = combinator_index
				result.options[option_key] = { option_def, combinator_index }
			end
		elseif entity_name == constants.pin_name then
			-- Store pin in lookup table for later resolution.
			local ic_index, pin_number =
				get_pin_info_from_tags(bp_entity.tags or EMPTY)
			if ic_index and pin_number then
				local bp_ic = bp_ics[ic_index]
				if not bp_ic then
					bp_ic = {}
					bp_ics[ic_index] = bp_ic
				end
				bp_ic[pin_number] = bp_index
				bp_pins[bp_index] = { ic_index, pin_number }
			end
		elseif entity_name == constants.ic_name then
			if not bp_ics[bp_index] then bp_ics[bp_index] = {} end
		end
	end

	-- PASS 2: RECURSION PASS
	---Map from BP pin indices within this IC to the created pad entities of the recursive IC.
	---@type {[uint]: uint[]}
	local pin_remap = {}
	for bp_index, pin_map in pairs(bp_ics) do
		-- Compile embbeded IC.
		local bp_entity = bp_entities[bp_index] --[[@as BlueprintEntity]]
		local ic_blueprint_string, nested_initial_options =
			get_ic_info_from_tags(bp_entity.tags)
		if not ic_blueprint_string then goto continue end
		local compiled = compile(
			ic_blueprint_string,
			nested_initial_options,
			level + 1,
			get_next_position
		)
		if not compiled then goto continue end

		local index_offset = #result_entities

		-- Transfer recursive entities
		for _, entity in ipairs(compiled.entities) do
			result_entities[#result_entities + 1] = entity
		end

		-- Transfer wires, compensate for index offset.
		for _, wire in pairs(compiled.wires) do
			wire[1] = wire[1] + index_offset
			wire[3] = wire[3] + index_offset
			result.wires[#result.wires + 1] = wire
		end

		-- Compute pin-to-pad mapping for the embedded IC
		for pin_number, bp_pin_index in pairs(pin_map) do
			local compiled_pads = compiled.pad_map[pin_number]
			if compiled_pads then
				pin_remap[bp_pin_index] = tlib.map(
					compiled_pads,
					function(connector_index) return connector_index + index_offset end
				)
			end
		end
		::continue::
	end

	-- PASS 3: WIRING PASS
	local wires_dedupe = {}

	---@return uint? single Single target entity within `entities`
	---@return uint[]? multi Multiple target `entities` (in case of pin remapping due to recursion)
	local function resolve_wire(bp_index)
		if not bp_index then return nil end
		local direct = bp_to_compiled[bp_index]
		if direct then return direct end

		local multi = pin_remap[bp_index]
		if multi then return nil, multi end
	end

	for _, bp_entity in pairs(bp_entities) do
		local wires = bp_entity.wires
		if not wires then goto continue_entities end
		for _, wire in pairs(wires) do
			local a_num = wire[1]
			local a_connector = wire[2]
			local b_num = wire[3]
			local b_connector = wire[4]

			local a_direct, a_multi = resolve_wire(a_num)
			local b_direct, b_multi = resolve_wire(b_num)
			if not a_direct and not a_multi then goto continue_wires end
			if not b_direct and not b_multi then goto continue_wires end

			-- Easy case
			if a_direct and b_direct then
				add_wire(
					result.wires,
					wires_dedupe,
					a_direct,
					a_connector,
					b_direct,
					b_connector
				)
				goto continue_wires
			end

			-- Crossproduct case
			a_multi = a_multi or { a_direct }
			b_multi = b_multi or { b_direct }
			for _, a_endpoint in pairs(a_multi) do
				for _, b_endpoint in pairs(b_multi) do
					add_wire(
						result.wires,
						wires_dedupe,
						a_endpoint,
						a_connector,
						b_endpoint,
						b_connector
					)
				end
			end

			::continue_wires::
		end

		::continue_entities::
	end

	return result
end

lib.compile = compile

return lib
