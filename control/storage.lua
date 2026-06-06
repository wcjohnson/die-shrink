local ps_lib = require("control.player-state")

---@alias PlayerIndex uint
---@alias SurfaceIndex uint
---@alias ThingID int64
---@alias UnitNumber int64
---@alias ID int64

---@class DieShrink.Storage
---@field players {[PlayerIndex]: DieShrink.PlayerState}
---@field ics {[ThingID]: DieShrink.IC}
---@field editor_sessions {[ID]: DieShrink.EditorSession}
---@field surface_to_session {[SurfaceIndex]: ID}
storage = {}

---@param player_index PlayerIndex
---@return DieShrink.PlayerState
function _G.get_or_create_player_state(player_index)
	if not storage.players then storage.players = {} end
	if not storage.players[player_index] then
		storage.players[player_index] = ps_lib.PlayerState:new(player_index)
	end
	return storage.players[player_index]
end

---@param player_index PlayerIndex
---@return DieShrink.PlayerState?
function _G.get_player_state(player_index)
	return storage.players and storage.players[player_index]
end

---@param thing_id ThingID
---@return DieShrink.IC?
function _G.get_ic_state(thing_id) return storage.ics and storage.ics[thing_id] end

function _G.get_or_create_ic_state(thing_id)
	local ics = storage.ics
	if not ics then
		ics = {}
		storage.ics = ics
	end
	local ic = ics[thing_id]
	if ic then return ic end
	ic = IC:new(thing_id)
	ics[thing_id] = ic
	return ic
end
