local class = require("lib.core.class").class
local ovl_lib = require("lib.core.overlay")
local pos_lib = require("lib.core.math.pos")
local constants = require("lib.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local strace = require("lib.core.strace")

---@class DieShrink.IC
---@field thing_id int
local IC = class("DieShrink.IC")
_G.IC = IC

function IC:new(thing_id)
	local obj =
		setmetatable({ thing_id = thing_id, connection_render_objects = {} }, self)
	storage.ics[thing_id] = obj
	return obj
end

function IC:destroy() storage.ics[self.thing_id] = nil end

return IC
