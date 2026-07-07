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
local VF = ultros.VFlow
local pad_sprite_name = "item/" .. constants.pad_name
local option_sprite_name = "item/" .. constants.option_name

local lib = {}

lib.EditorUi = relm.define("EditorUi", function(props)
	local root_id = props.root_id
	local player_index = props.player_index
	local player = game and game.get_player(player_index)
	if (not player) or not player.valid then return nil end
	local player_state = get_player_state(player_index)
	if not player_state then return nil end
	local session = props.session --[[@as DieShrink.EditorSession]]
	local ic = session.ic --[[@as DieShrink.IC]]
	local ic_id = ic.thing_id

	-- Window management
	local function close_me() relm.root_destroy(root_id) end
	local close_and_save_pos = ultros.use_memoized_window_position(
		close_me,
		function()
			local st = get_player_state(player_index)
			return st and st.editor_window_position or { 0, 0 }
		end,
		function(xy)
			local st = get_or_create_player_state(player_index)
			st.editor_window_position = xy
		end,
		function(elt) elt.location = { 0, 0 } end
	)
	relm_util.use_event_handler(
		"dieshrink.player_editor_session_popped",
		function(_me, _, ps)
			if
				ps
				and ps.player_index == player_index
				and not ps:get_current_editor_session_id()
			then
				close_and_save_pos()
			else
				relm.paint(_me)
			end
		end
	)
	relm_util.use_event_handler(
		"dieshrink.player_editor_session_pushed",
		function(_me, _, ps)
			if ps and ps.player_index == player_index then relm.paint(_me) end
		end
	)
	local function pop_one_editor() close_current_editor_session(player_index) end

	-- Editables
	relm_util.use_event_handler(
		"dieshrink.ic_labels_changed",
		function(_me, _, _ic)
			if _ic and _ic.thing_id == ic_id then relm.paint(_me) end
		end
	)

	local icons = ic:get_icons() or {}

	local function set_icon_value(index, signal)
		icons[index] = signal

		local compact = {}
		for _, icon in ipairs(icons) do
			if icon then compact[#compact + 1] = icon end
		end
		ic:set_icons(compact)
	end

	return ultros.WindowFrame({
		caption = { "die-shrink-editor.title" },
		closable = false,
	}, {
		HF({ width = 300 }, {
			ultros.SpriteButton({
				sprite = pad_sprite_name,
				tooltip = { "die-shrink-editor.pick-pad" },
				on_click = function()
					cursor_lib.set_cursor_ghost(player, constants.pad_name)
				end,
			}),
			ultros.SpriteButton({
				sprite = option_sprite_name,
				tooltip = { "die-shrink-editor.pick-option" },
				on_click = function()
					cursor_lib.set_cursor_ghost(player, constants.option_name)
				end,
			}),
		}),
		ultros.Label({
			"",
			"Editor stack:",
			serpent.line(player_state.editor_session_stack),
		}),
		ultros.Labeled({ caption = "Label" }, {
			ultros.UncontrolledInput({
				value = ic:get_label() or "",
				on_change = function(_, new_label)
					local value = tostring(new_label or "")
					if value == "" then
						ic:set_label(nil)
					else
						ic:set_label(value)
					end
				end,
			}),
		}),
		VF({
			ultros.Label("Icons"),
			HF({ width = 300 }, {
				ultros.SignalPicker({
					value = icons[1],
					on_change = function(_, signal) set_icon_value(1, signal) end,
				}),
				ultros.SignalPicker({
					value = icons[2],
					on_change = function(_, signal) set_icon_value(2, signal) end,
				}),
				ultros.SignalPicker({
					value = icons[3],
					on_change = function(_, signal) set_icon_value(3, signal) end,
				}),
				ultros.SignalPicker({
					value = icons[4],
					on_change = function(_, signal) set_icon_value(4, signal) end,
				}),
			}),
		}),
		ultros.Button({
			caption = "Exit",
			on_click = pop_one_editor,
		}),
	})
end)

---@param session DieShrink.EditorSession
function _G.open_editor_ui(session)
	local player = game.get_player(session.player.index)
	if not player then return end
	-- Already open
	if player.gui.screen["DieShrinkEditorUi"] then return end
	relm.root_create(
		player.gui.screen,
		"DieShrinkEditorUi",
		"EditorUi",
		{ session = session }
	)
end

event.bind(
	"dieshrink.editor_session_opened",
	function(session) open_editor_ui(session) end
)

return lib
