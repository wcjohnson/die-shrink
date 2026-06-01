--------------------------------------------------------------------------------
-- UI when inside editor surface.
--------------------------------------------------------------------------------

local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")
local event = require("lib.core.event")
local constants = require("lib.constants")
local cursor_lib = require("lib.core.cursor")

local HF = ultros.HFlow
local pad_sprite_name = "item/" .. constants.pad_name

local lib = {}

lib.EditorUi = relm.define("EditorUi", function(props)
	local root_id = props.root_id
	local player_index = props.player_index
	local player = game.get_player(player_index)
	local ic = props.ic --[[@as DieShrink.IC]]

	if (not player) or not player.valid then return end

	-- Window management
	local function close_me()
		relm.root_destroy(root_id)
		close_editor_session(player_index)
	end
	local handle_close = ultros.use_memoized_window_position(close_me, function()
		local st = get_player_state(player_index)
		return st and st.editor_window_position or { 0, 0 }
	end, function(xy)
		local st = get_or_create_player_state(player_index)
		st.editor_window_position = xy
	end, function(elt) elt.location = { 0, 0 } end)
	relm_util.use_event_handler(
		"dieshrink.editor_session_closed",
		function(_, _, _player_index)
			if _player_index == player_index then relm.root_destroy(root_id) end
		end
	)

	return ultros.WindowFrame({
		caption = { "die-shrink-editor.title" },
		on_close = handle_close,
	}, {
		HF({ width = 300 }, {
			ultros.SpriteButton({
				sprite = pad_sprite_name,
				tooltip = { "die-shrink-editor.pick-pad" },
				on_click = function()
					cursor_lib.set_cursor_ghost(player, constants.pad_name)
				end,
			}),
		}),
	})
end)

---@param player LuaPlayer
---@param ic DieShrink.IC
function _G.open_editor_ui(player, ic)
	-- Already open
	if player.gui.screen["DieShrinkEditorUi"] then return end
	relm.root_create(
		player.gui.screen,
		"DieShrinkEditorUi",
		"EditorUi",
		{ ic = ic }
	)
end

return lib
