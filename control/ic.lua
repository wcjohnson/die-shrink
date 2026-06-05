local class = require("lib.core.class").class
local event = require("lib.core.event")
local ovl_lib = require("lib.core.overlay")
local pos_lib = require("lib.core.math.pos")
local constants = require("lib.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local strace = require("lib.core.strace")

---@class DieShrink.IC
---@field thing_id ThingID
---@field n_pins uint
local IC = class("DieShrink.IC")
_G.IC = IC

function IC:new(thing_id)
	local obj = setmetatable({ thing_id = thing_id, n_pins = 0 }, self)
	local ics = storage.ics
	if not ics then
		ics = {}
		storage.ics = ics
	end
	ics[thing_id] = obj
	return obj
end

function IC:get_n_pins() return self.n_pins end

function IC:set_n_pins(n)
	if self.n_pins == n then return end
	if self.n_pins ~= 0 then
		strace.error(
			"Attempted to change number of pins on IC",
			self.thing_id,
			"from",
			self.n_pins,
			"to",
			n
		)
		return
	end
	self.n_pins = n
	event.raise("dieshrink.ic_pins_changed", self)
end

function IC:destroy() storage.ics[self.thing_id] = nil end

return IC
