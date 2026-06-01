local class = require("lib.core.class").class
local event = require("lib.core.event")
local ovl_lib = require("lib.core.overlay")
local pos_lib = require("lib.core.math.pos")
local constants = require("lib.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local strace = require("lib.core.strace")

---@class DieShrink.IC
---@field thing_id ThingID
local IC = class("DieShrink.IC")
_G.IC = IC

function IC:new(thing_id)
	local obj = setmetatable({ thing_id = thing_id }, self)
	local ics = storage.ics
	if not ics then
		ics = {}
		storage.ics = ics
	end
	ics[thing_id] = obj
	return obj
end

function IC:destroy() storage.ics[self.thing_id] = nil end

event.bind(
	"die-shrink-on_initialized",
	---@param ev things.EventData.on_initialized
	function(ev)
		-- Create IC state
		local ic = IC:new(ev.id)
	end
)

event.bind(
	"die-shrink-on_status",
	---@param ev things.EventData.on_status
	function(ev)
		strace.trace("die-shrink-on_status", ev)
		if ev.new_status == "destroyed" then
			-- Destroy IC state
			local ic = get_ic_state(ev.thing.id)
			if ic then ic:destroy() end
			return
		end
		-- local entity, ic = get_ic_info(ev.thing, false)

		if ev.old_status == "ghost" and ev.new_status == "real" then
			-- Connect to all neighbors on revival.
		end
	end
)

event.bind(
	"die-shrink-on_children_normalized",
	---@param ev things.EventData.on_children_normalized
	function(ev)
		strace.trace("die-shrink-on_children_normalized", ev)
		-- Reconnect to all neighbors if not ghost
		if ev.status == "real" then
			local _, pins = remote.call("things", "get_children", ev.id)
			-- Disconnect all neighbors
			-- Connect all neighbors
		end
	end
)

return IC
