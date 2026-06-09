local class = require("lib.core.class").class
local ovl_lib = require("lib.core.overlay")
local pos_lib = require("lib.core.math.pos")
local strace = require("lib.core.strace")
local event = require("lib.core.event")

local pos_new = pos_lib.pos_new
local pos_add = pos_lib.pos_add
local pos_normalize = pos_lib.pos_normalize
local pos_scale = pos_lib.pos_scale
local dir_from = pos_lib.dir_from

local lib = {}

---@class DieShrink.PlayerState
---@field player_index uint Index of the player this state belongs to
---@field editor_session_stack ID[] Stack of editor session IDs for this player.
---@field pin_labels? LuaRenderObject[] Pin label rendering objects
---@field editor_window_position? GuiLocation Position of the editor window
---@field ic_window_position? GuiLocation Position of the IC window
local PlayerState = class("DieShrink.PlayerState")
lib.PlayerState = PlayerState

---@param player_index uint
function PlayerState:new(player_index)
	local instance = {}
	setmetatable(instance, self)
	instance.player_index = player_index
	instance.editor_session_stack = {}
	return instance
end

---@param id ID
function PlayerState:push_editor_session(id)
	self.editor_session_stack[#self.editor_session_stack + 1] = id
	event.raise("dieshrink.player_editor_session_pushed", self, id)
end

---@return ID?
function PlayerState:pop_editor_session()
	if #self.editor_session_stack == 0 then return nil end
	local id = table.remove(self.editor_session_stack)
	event.raise("dieshrink.player_editor_session_popped", self, id)
	return id
end

---@return ID?
function PlayerState:get_current_editor_session_id()
	return self.editor_session_stack[#self.editor_session_stack]
end

---@return DieShrink.EditorSession?
function PlayerState:get_current_editor_session()
	local id = self:get_current_editor_session_id()
	if not id then return nil end
	return storage.editor_sessions and storage.editor_sessions[id]
end

function PlayerState:clear_pin_labels()
	ovl_lib.destroy_render_objects(self.pin_labels)
	self.pin_labels = nil
end

local BASE_LABELS = {
	"1",
	"2",
	"3",
	"4",
	"5",
	"6",
	"7",
	"8",
	"9",
	"10",
	"11",
	"12",
	"13",
	"14",
	"15",
	"16",
}

local default_dir_orientations =
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local default_dir_aligns = {
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
	"center",
}
local default_dir_offsets = {
	{ 0, -0.6 },
	{ 0.15, -0.6 },
	{ 0.3, -0.3 },
	{ 0.15, 0 },
	{ 0, 0 },
	{ -0.15, 0 },
	{ -0.3, -0.3 },
	{ -0.15, -0.6 },
	{ 0, -0.6 },
	{ 0.15, -0.6 },
	{ 0.3, -0.3 },
	{ 0.15, 0 },
	{ 0, 0 },
	{ -0.15, 0 },
	{ -0.3, -0.3 },
	{ -0.15, -0.6 },
}
local custom_dir_orientations = {
	6 / 8,
	7 / 8,
	0 / 8,
	1 / 8,
	6 / 8,
	7 / 8,
	0 / 8,
	1 / 8,
	6 / 8,
	7 / 8,
	0 / 8,
	1 / 8,
	6 / 8,
	7 / 8,
	0 / 8,
	1 / 8,
}
local custom_dir_aligns = {
	"left",
	"left",
	"left",
	"left",
	"right",
	"right",
	"right",
	"right",
	"left",
	"left",
	"left",
	"left",
	"right",
	"right",
	"right",
	"right",
}
local custom_dir_offsets = {
	{ -0.3, -0.15 },
	{ -0.15, -0.3 },
	{ 0.15, -0.3 },
	{ 0.3, -0.15 },
	{ -0.3, 0.15 },
	{ -0.3, -0.15 },
	{ -0.15, -0.3 },
	{ 0.15, -0.3 },
	{ -0.3, -0.15 },
	{ -0.15, -0.3 },
	{ 0.15, -0.3 },
	{ 0.3, -0.15 },
	{ -0.3, 0.15 },
	{ -0.3, -0.15 },
	{ -0.15, -0.3 },
	{ 0.15, -0.3 },
}

---@param parent things.ThingSummary
---@param children things.ThingChildrenSummary?
function PlayerState:render_pin_labels(parent, children)
	local parent_entity = parent.entity
	if not parent_entity then return end
	local parent_pos = parent_entity.position
	if not children then
		_, children = remote.call("things", "get_children", parent.id)
	end
	if not children then return end
	local labels = BASE_LABELS
	local ic = get_ic_state(parent.id)
	if ic and ic.pin_labels and next(ic.pin_labels) then
		labels = ic.pin_labels
	end

	self:clear_pin_labels()
	local ros = {}
	for index, child in pairs(children) do
		local nindex = tonumber(index)
		local entity = child.entity
		if entity then
			local text = labels[nindex] or labels[index] or BASE_LABELS[nindex] or "?"
			local child_pos = entity.position
			local dir = math.floor(dir_from(parent_pos, child_pos) / 2) + 1
			local orientations = (#text > 1) and custom_dir_orientations
				or default_dir_orientations
			local offsets = (#text > 1) and custom_dir_offsets or default_dir_offsets
			local aligns = (#text > 1) and custom_dir_aligns or default_dir_aligns
			ros[#ros + 1] = rendering.draw_text({
				text = text,
				surface = entity.surface,
				target = { entity = entity, offset = offsets[dir] or { 0, 0 } },
				orientation = orientations[dir] or 0,
				color = { r = 1, g = 1, b = 1 },
				alignment = aligns[dir] or "center",
				players = { self.player_index },
				use_rich_text = true,
			})
		end
	end
	self.pin_labels = ros
end

return lib
