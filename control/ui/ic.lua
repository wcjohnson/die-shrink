--------------------------------------------------------------------------------
-- UI when an IC is clicked
--------------------------------------------------------------------------------

local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")
local event = require("lib.core.event")
local constants = require("lib.constants")
local strace = require("lib.core.strace")

local HF = ultros.HFlow

local lib = {}

lib.IcUi = relm.define("IcUi", function(props)
	local root_id = props.root_id
	local player_index = props.player_index
	local player = game.get_player(player_index)
	local ic = props.ic --[[@as DieShrink.IC]]

	if (not player) or not player.valid then return end

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
			if _session and _session.player.index == player_index then
				close_me()
			end
		end
	)

	return ultros.WindowFrame({
		caption = "IC",
		on_close = handle_close,
	}, {
		HF({ width = 300 }, {
			ultros.Button({
				caption = "Open Editor",
				on_click = function() open_editor_session(player_index, ic) end,
			}),
		}),
	})
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
