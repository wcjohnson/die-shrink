local class = require("lib.core.class").class
local event = require("lib.core.event")
local ovl_lib = require("lib.core.overlay")
local pos_lib = require("lib.core.math.pos")
local constants = require("lib.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local strace = require("lib.core.strace")
local compiler = require("control.compiler")
local linker = require("control.linker")
local tlib = require("lib.core.table")

---@class DieShrink.IC
---@field thing_id ThingID
---@field alive boolean
---@field n_pins uint
---@field linked? DieShrink.LinkerResult Linker result for this IC.
local IC = class("DieShrink.IC")
_G.IC = IC

function IC:new(thing_id)
	local obj =
		setmetatable({ thing_id = thing_id, n_pins = 0, alive = false }, self)
	local ics = storage.ics
	if not ics then
		ics = {}
		storage.ics = ics
	end
	ics[thing_id] = obj
	return obj
end

---Compile and link the IC.
function IC:link(force_recompile)
	strace.trace("Linking IC", self.thing_id)
	if force_recompile then
		strace.trace("Unlinking IC", self.thing_id, "due to force recompile")
		self:unlink()
	end
	if self.linked then
		strace.trace("IC", self.thing_id, "is already linked, skipping")
		return
	end
	if self.n_pins == 0 then
		strace.trace("IC", self.thing_id, "has not been configured yet.")
		return
	end
	local _, thing = remote.call("things-metadata-v1", "get", self.thing_id)
	if (not thing) or thing.status ~= "real" then
		strace.info("IC", self.thing_id, "is not real, skipping link")
		return
	end
	local bp_string = thing.tags and thing.tags.blueprint --[[@as string?]]
	if not bp_string then
		strace.trace("IC", self.thing_id, "is empty")
		return
	end
	local _, children = remote.call("things", "get_children", thing.id)
	if not children then
		strace.error("IC", self.thing_id, "is missing children")
		return
	end
	local pin_entities = tlib.t_map_t(
		children,
		function(key, child) return tonumber(key), child.entity end
	) --[[@as table<uint, LuaEntity>]]
	if #pin_entities ~= self.n_pins then
		strace.error(
			"Number of child entities",
			#pin_entities,
			"does not match n_pins",
			self.n_pins,
			"for IC with thing_id",
			self.thing_id
		)
		return
	end
	local compiled = compiler.compile(bp_string)
	if not compiled then
		strace.error("Failed to compile IC with thing_id", self.thing_id)
		return
	end
	strace.trace(
		"Compiled IC",
		self.thing_id,
		"with",
		#compiled.entities,
		"entities and",
		#compiled.wires,
		"wires"
	)
	strace.trace("Compiled to", compiled)
	self.linked = linker.link(
		compiled,
		thing.entity.surface,
		thing.entity.force --[[@as LuaForce]],
		thing.entity.position,
		pin_entities
	)
end

---Destroy compiled circuit and links
function IC:unlink()
	if self.linked then
		linker.unlink(self.linked)
		self.linked = nil
	end
end

---Disconnect pin wires from linked circuit.
function IC:disconnect_pins()
	if not self.linked then return end
	linker.disconnect(self.linked)
end

---Reconnect pin wires to linked circuit.
function IC:reconnect_pins()
	if not self.linked then return end
	linker.reconnect(self.linked)
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

function IC:destroy()
	self:unlink()
	storage.ics[self.thing_id] = nil
end

--------------------------------------------------------------------------------
-- IC LIFECYCLE
--------------------------------------------------------------------------------

event.bind(
	"die-shrink-on_initialized",
	---@param thing things.EventData.on_initialized
	function(thing)
		-- Create IC state
		local ic = get_or_create_ic_state(thing.id)
		-- Initial n_pins
		local n_pins_tag = thing.tags and thing.tags.n_pins
		if n_pins_tag then
			ic.n_pins = n_pins_tag --[[@as uint]]
		else
			local _, n_children = remote.call("things", "get_num_children", thing.id)
			n_children = n_children or 0
			if n_children > 8 then
				n_children = 16
			elseif n_children > 4 then
				n_children = 8
			elseif n_children > 2 then
				n_children = 4
			elseif n_children > 0 then
				n_children = 2
			else
				n_children = 0
			end
			ic.n_pins = n_children
		end
		strace.trace("Initialized ic", ic.thing_id, "with", ic.n_pins, "pins")
		-- Create pins
		check_pins(thing, ic:get_n_pins(), ic)
	end
)

event.bind("dieshrink.ic_pins_changed", function(ic)
	local _, thing = remote.call("things", "get", ic.thing_id)
	if not thing then return end
	local n_pins = ic:get_n_pins()
	remote.call("things", "set_tag", thing.id, "n_pins", n_pins)
	check_pins(thing, n_pins, ic)
end)

event.bind(
	"die-shrink-on_status",
	---@param ev things.EventData.on_status
	function(ev)
		strace.trace("die-shrink-on_status", ev)
		local old_status = ev.old_status
		local new_status = ev.new_status
		local ic = get_or_create_ic_state(ev.thing.id)

		if new_status == "destroyed" then
			ic:destroy()
			return
		end

		-- Check pins in all non-void states
		if
			old_status == "void"
			or new_status == "ghost"
			or new_status == "real"
		then
			check_pins(ev.thing, ic:get_n_pins(), ic)
		end

		-- Unlink if void or ghosted
		if new_status == "void" or new_status == "ghost" then
			strace.trace(
				"Unlinking IC",
				ic.thing_id,
				"due to status change to",
				new_status
			)
			ic:unlink()
		end

		-- Link if real
		if new_status == "real" then
			strace.trace("Linking IC", ic.thing_id, "due to status change to real")
			ic:link()
		end
	end
)

event.bind("dieshrink.ic_children_normalized", function(ic)
	local _, status = remote.call("things-metadata-v1", "get_status", ic.thing_id)
	if status == "real" then
		-- Pins changed so recompile.
		-- TODO: make more efficient; we don't really need full recompile?
		strace.trace("Recompiling IC", ic.thing_id, "due to children normalized")
		ic:link(true)
	else
		ic:unlink()
	end
end)

event.bind(
	"die-shrink-on_tags_changed",
	---@param ev things.EventData.on_tags_changed
	function(ev)
		local ic = get_ic_state(ev.thing.id)
		if not ic then return end
		if
			(ev.new_tags and ev.new_tags.blueprint or "")
			~= (ev.old_tags and ev.old_tags.blueprint or "")
		then
			strace.trace("Blueprint tag changed for IC", ic.thing_id, "relinking")
			ic:link(true)
		end
	end
)

return IC
