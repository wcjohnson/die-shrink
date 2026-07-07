--------------------------------------------------------------------------------
-- UI when an IC is clicked
--------------------------------------------------------------------------------

local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")
local event = require("lib.core.event")
local constants = require("lib.constants")
local strace = require("lib.core.strace")
local tlib = require("lib.core.table")

local HF = ultros.HFlow
local VF = ultros.VFlow
local Pr = relm.Primitive
local EMPTY = tlib.EMPTY

local lib = {}

relm.define("IcOption.input", function(props)
	local def = props.option_def --[[@as DieShrink.InputOptionDefinition]]
	local choice = props.option_choice --[[@as DieShrink.InputOptionChoice]]
	local key = props.key --[[@as string]]
	local ic = props.ic --[[@as DieShrink.IC]]

	return {
		ultros.BoldLabel(def.label or "Unlabelled input"),
		Pr({ type = "line" }),
		ultros.UncontrolledInput({
			value = choice and choice.value,
			numeric = true,
			on_change = function(_, new_value)
				ic:set_option_choice(key, { value = tonumber(new_value) })
			end,
		}),
	}
end)

relm.define("IcOption.signals", function(props)
	local def = props.option_def --[[@as DieShrink.SignalsOptionDefinition]]
	local choice = props.option_choice --[[@as DieShrink.SignalsOptionChoice]]
	local key = props.key --[[@as string]]
	local ic = props.ic --[[@as DieShrink.IC]]

	return {
		ultros.BoldLabel(def.label or "Unlabelled signals"),
		Pr({ type = "line" }),
		ultros.SignalCountsInput({
			column_count = 8,
			signals = choice and choice.signals or EMPTY,
			counts = choice and choice.counts or EMPTY,
			on_change = function(_, signals, counts)
				ic:set_option_choice(key, { signals = signals, counts = counts })
			end,
		}),
	}
end)

lib.IcUi = relm.define("IcUi", function(props)
	local root_id = props.root_id
	local player_index = props.player_index
	local player = game.get_player(player_index)
	local ic = props.ic --[[@as DieShrink.IC]]
	local n_pins = ic:get_n_pins()
	local option_choices = ic.option_choices or {}
	local option_defs = ic.option_definitions or {}

	if (not player) or not player.valid then return nil end

	-- Window management
	local function close_me() relm.root_destroy(root_id) end

	local handle_close = ultros.use_memoized_window_position(close_me, function()
		local st = get_player_state(player_index)
		return st and st.ic_window_position
	end, function(xy)
		local st = get_or_create_player_state(player_index)
		st.ic_window_position = xy
	end, function(elt) elt.force_auto_center() end)

	ultros.use_close_on_gui_closed(player_index, close_me, false)
	ultros.use_player_opened(player_index)

	relm_util.use_event_handler(
		"dieshrink.editor_session_opened",
		function(_, _, _session)
			if _session and _session.player.index == player_index then close_me() end
		end
	)

	relm_util.use_event_handler("dieshrink.ic_pins_changed", function(_me, _, _ic)
		if _ic.thing_id == ic.thing_id then relm.paint(_me) end
	end)
	relm_util.use_event_handler(
		"dieshrink.ic_options_changed",
		function(_me, _, _ic)
			if _ic.thing_id == ic.thing_id then relm.paint(_me) end
		end
	)

	local elts = {}
	local option_keys = {}
	for key, _ in pairs(option_defs) do
		option_keys[#option_keys + 1] = key
	end
	table.sort(option_keys)

	for _, key in ipairs(option_keys) do
		local option_def = option_defs[key] and option_defs[key][1]
		local option_type = option_def and option_def.type
		local option_choice = option_choices[key] or {}
		if option_type then
			elts[#elts + 1] = relm.element("IcOption." .. option_type, {
				option_def = option_def,
				option_choice = option_choice,
				key = key,
				ic = ic,
			})
		end
	end

	elts[#elts + 1] = ultros.CallIf(n_pins == 0, function()
		return HF({ width = 300 }, {
			ultros.Button({
				caption = "2 pins",
				width = 300 / 4,
				on_click = function() ic:set_n_pins(2) end,
			}),
			ultros.Button({
				caption = "4 pins",
				width = 300 / 4,
				on_click = function() ic:set_n_pins(4) end,
			}),
			ultros.Button({
				caption = "8 pins",
				width = 300 / 4,
				on_click = function() ic:set_n_pins(8) end,
			}),
			ultros.Button({
				caption = "16 pins",
				width = 300 / 4,
				on_click = function() ic:set_n_pins(16) end,
			}),
		})
	end)

	elts[#elts + 1] = ultros.CallIf(n_pins > 0, function()
		return ultros.Button({
			caption = "Open Editor",
			on_click = function() open_editor_session(player_index, ic) end,
		})
	end)

	return ultros.WindowFrame({
		caption = ic:get_label() or "IC",
		on_close = handle_close,
		width = 345,
	}, elts)
end)

---@param player LuaPlayer
---@param ic DieShrink.IC
function _G.open_ic_ui(player, ic)
	-- Already open
	if player.gui.screen["DieShrinkIcUi"] then return end
	relm.root_create(player.gui.screen, "DieShrinkIcUi", "IcUi", { ic = ic })
end

event.bind("die-shrink-click", function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end
	if not player.is_cursor_empty() then return end

	local selected = player.selected
	if not selected or not selected.valid then return end
	if selected.name ~= constants.ic_name then return end

	local get_error, thing = remote.call("things", "get", selected)
	if not thing or not thing.entity then return end
	local ic = get_ic_state(thing.id)
	if not ic then return end

	open_ic_ui(player, ic)
end)

return lib
