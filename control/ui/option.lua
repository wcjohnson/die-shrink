--------------------------------------------------------------------------------
-- UI when an internal option editor is clicked
--------------------------------------------------------------------------------

local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")
local event = require("lib.core.event")
local constants = require("lib.constants")
local strace = require("lib.core.strace")
local tlib = require("lib.core.table")

local assign = tlib.assign
local HF = ultros.HFlow

local lib = {}

local mode_opts = {
	{ key = "input", caption = "Numeric Input" },
	{ key = "signals", caption = "Signal Inputs" },
}

relm.define("OptionUi.signals", function(props)
	local session = props.session --[[@as DieShrink.EditorSession]]
	local ic = props.ic --[[@as DieShrink.IC]]
	local thing_id = props.thing_id

	local current_def = session:get_option_definition(thing_id) --[[@as DieShrink.SignalsOptionDefinition]]

	return {
		ultros.Labeled({ caption = "Label" }, {
			ultros.UncontrolledInput({
				value = current_def.label,
				on_change = function(_, new_label)
					session:set_option_definition(
						thing_id,
						assign({}, current_def, { label = tostring(new_label) })
					)
				end,
			}),
		}),
	}
end)

relm.define("OptionUi.input", function(props)
	local session = props.session --[[@as DieShrink.EditorSession]]
	local ic = props.ic --[[@as DieShrink.IC]]
	local thing_id = props.thing_id

	local current_def = session:get_option_definition(thing_id) --[[@as DieShrink.InputOptionDefinition]]

	return {
		ultros.Labeled({ caption = "Label" }, {
			ultros.UncontrolledInput({
				value = current_def.label,
				on_change = function(_, new_label)
					session:set_option_definition(
						thing_id,
						assign({}, current_def, { label = tostring(new_label) })
					)
				end,
			}),
		}),
		ultros.Labeled({ caption = "Signal" }, {
			ultros.SignalPicker({
				value = current_def.signal,
				on_change = function(_, new_signal)
					if not new_signal then return end
					session:set_option_definition(
						thing_id,
						assign({}, current_def, { signal = new_signal })
					)
				end,
			}),
		}),
	}
end)

lib.OptionUi = relm.define("OptionUi", function(props)
	local root_id = props.root_id
	local player_index = props.player_index
	local player = game.get_player(player_index)
	if (not player) or not player.valid then return end
	local session = props.session --[[@as DieShrink.EditorSession]]
	local ic = props.ic --[[@as DieShrink.IC]]
	local thing_id = props.thing_id

	local current_def = session:get_option_definition(thing_id)
	local def_type = current_def and current_def.type

	-- Window management
	local function close_me() relm.root_destroy(root_id) end

	ultros.use_auto_center_on_open()
	ultros.use_close_on_gui_closed(player_index, close_me, false)
	ultros.use_player_opened(player_index)
	relm_util.use_event_handler({
		"dieshrink.player_editor_session_pushed",
		"dieshrink.player_editor_session_popped",
	}, function(_, _, ps)
		if ps and ps.player_index == player_index then close_me() end
	end)

	-- Repaint
	relm_util.use_event_handler(
		"dieshrink.editor_session_option_changed",
		function(_me, _, _session, _unit_number)
			if _session == session and _unit_number == thing_id then
				relm.paint(_me)
			end
		end
	)

	return ultros.WindowFrame({
		caption = "Option",
		on_close = close_me,
		width = 300,
	}, {
		ultros.Labeled({ caption = "Mode" }, {
			ultros.Dropdown({
				options = mode_opts,
				value = current_def and current_def.type,
				on_change = function(_, new_mode)
					if not new_mode then return end
					session:set_option_definition(thing_id, { type = new_mode })
				end,
			}),
		}),
		ultros.CallIf(
			def_type,
			function()
				return relm.element(
					"OptionUi." .. def_type,
					{ session = session, ic = ic, thing_id = thing_id }
				)
			end
		),
	})
end)

---@param player LuaPlayer
---@param ic DieShrink.IC
---@param session DieShrink.EditorSession
---@param thing_id uint
function _G.open_option_ui(player, ic, session, thing_id)
	-- Already open
	if player.gui.screen["DieShrinkOptionUi"] then return end
	relm.root_create(
		player.gui.screen,
		"DieShrinkOptionUi",
		"OptionUi",
		{ ic = ic, session = session, thing_id = thing_id }
	)
end

event.bind(defines.events.on_gui_opened, function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end

	local selected = ev.entity --[[@as LuaEntity?]]
	if not selected then return end
	if selected.name ~= constants.option_name then return end

	-- Close any existing ui
	player.opened = nil

	local session = get_editor_session_for_surface(selected.surface_index)
	if not session then return end
	local _, thing_id = remote.call("things", "get_thing_id", selected)
	if not thing_id then return end

	open_option_ui(player, session.ic, session, thing_id)
end)

return lib
