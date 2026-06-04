--------------------------------------------------------------------------------
-- UI when an internal pad is clicked
--------------------------------------------------------------------------------

local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")
local event = require("lib.core.event")
local constants = require("lib.constants")
local strace = require("lib.core.strace")

local HF = ultros.HFlow

local lib = {}

lib.PadUi = relm.define("PadUi", function(props)
	local root_id = props.root_id
	local player_index = props.player_index
	local player = game.get_player(player_index)
	if (not player) or not player.valid then return end
	local session = props.session --[[@as DieShrink.EditorSession]]
	local ic = props.ic --[[@as DieShrink.IC]]
	local pad_unit_number = props.pad_unit_number
	local current_pin = session:get_pad_pin(pad_unit_number)
	local pin_opts = {}
	for i = 1, ic:get_n_pins() do
		pin_opts[i] = { key = i, caption = tostring(i) }
	end

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
		"dieshrink.editor_session_pad_changed",
		function(_me, _, _session, _unit_number)
			if _session == session and _unit_number == pad_unit_number then
				relm.paint(_me)
			end
		end
	)

	return ultros.WindowFrame({
		caption = "Pad",
		on_close = close_me,
	}, {
		HF({ width = 300 }, {
			ultros.Dropdown({
				options = pin_opts,
				value = current_pin,
				on_change = function(_, pin) session:set_pad_pin(pad_unit_number, pin) end,
			}),
		}),
	})
end)

---@param player LuaPlayer
---@param ic DieShrink.IC
---@param session DieShrink.EditorSession
---@param pad_unit_number uint
function _G.open_pad_ui(player, ic, session, pad_unit_number)
	-- Already open
	if player.gui.screen["DieShrinkPadUi"] then return end
	relm.root_create(
		player.gui.screen,
		"DieShrinkPadUi",
		"PadUi",
		{ ic = ic, session = session, pad_unit_number = pad_unit_number }
	)
end

event.bind(defines.events.on_gui_opened, function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end

	local selected = ev.entity --[[@as LuaEntity?]]
	if not selected then return end
	if selected.name ~= constants.pad_name then return end

	local session = get_editor_session_for_surface(selected.surface_index)
	if not session then return end

	-- Close any existing ui
	player.opened = nil

	open_pad_ui(player, session.ic, session, selected.unit_number)
end)

return lib
