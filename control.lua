local strace = require("lib.core.strace")
local relm = require("lib.core.relm.relm")
local event = require("lib.core.event")

relm.bootstrap_with_core_events(event)
strace.set_handler(strace.standard_log_handler)

local entities_lib = require("lib.core.entities")

require("control.ic")
require("control.storage")
require("control.editor")
require("control.pins")

require("control.ui.ic")
require("control.ui.editor")
require("control.ui.pad")
require("control.ui.option")

-- Enable support for the Global Variable Viewer debugging mod, if it is
-- installed.
if script.active_mods["gvv"] then require("__gvv__.gvv")() end

-- UI pos reset
commands.add_command(
	"die-shrink-reset-ui",
	"Reset the UI position for the Die Shrink mod.",
	function(x)
		local player_index = x.player_index
		if not player_index then return end
		local player_data = storage.players[player_index]
		if not player_data then return end

		player_data.editor_window_position = nil
		player_data.ic_window_position = nil
	end
)
