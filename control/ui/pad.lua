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
	if (not player) or not player.valid then return nil end
	local session = props.session --[[@as DieShrink.EditorSession]]
	local ic = props.ic --[[@as DieShrink.IC]]
	local pad_thing_id = props.pad_thing_id

	-- Pin info
	local current_pin = session:get_pad_pin(pad_thing_id)
	local pin_opts = {}
	for i = 1, ic:get_n_pins() do
		pin_opts[i] = { key = i, caption = tostring(i) }
	end

	-- Label
	local label_value = session:get_pad_label(pad_thing_id) or ""
	local set_label = function(_, new_label)
		session:set_pad_label(pad_thing_id, new_label)
	end

	-- Window management
	local function close_me() relm.root_destroy(root_id) end

	ultros.use_auto_center_on_open()
	ultros.use_close_on_gui_closed(player_index, close_me, false)
	ultros.use_player_opened(player_index)
	-- XXX: TYPES: GOOD/EVIL type bug again in a different form
	---@diagnostic disable-next-line: missing-fields
	relm_util.use_event_handler({
		"dieshrink.player_editor_session_pushed",
		"dieshrink.player_editor_session_popped",
	}, function(_, _, ps)
		if ps and ps.player_index == player_index then close_me() end
	end)

	-- Repaint
	relm_util.use_event_handler(
		"dieshrink.editor_session_pad_changed",
		function(_me, _, _session, _id)
			if _session == session and _id == pad_thing_id then relm.paint(_me) end
		end
	)

	return ultros.WindowFrame({
		caption = "Pad",
		on_close = close_me,
		width = 300,
	}, {
		ultros.Labeled({ caption = "Pin number" }, {
			ultros.Dropdown({
				options = pin_opts,
				value = current_pin,
				on_change = function(_, pin) session:set_pad_pin(pad_thing_id, pin) end,
			}),
		}),
		ultros.Labeled({ caption = "Pin label" }, {
			ultros.UncontrolledInput({
				value = label_value,
				width = 200,
				on_change = set_label,
				icon_selector = true,
			}),
		}),
	})
end)

---@param player LuaPlayer
---@param ic DieShrink.IC
---@param session DieShrink.EditorSession
---@param pad_thing_id uint
function _G.open_pad_ui(player, ic, session, pad_thing_id)
	-- Already open
	if player.gui.screen["DieShrinkPadUi"] then return end
	relm.root_create(
		player.gui.screen,
		"DieShrinkPadUi",
		"PadUi",
		{ ic = ic, session = session, pad_thing_id = pad_thing_id }
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
	local _, thing_id = remote.call("things", "get_thing_id", selected)
	if not thing_id then return end

	-- Close any existing ui
	player.opened = nil

	open_pad_ui(player, session.ic, session, thing_id)
end)

return lib
