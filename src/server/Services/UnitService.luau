--!strict
local UnitService = { units = {} }
function UnitService:Init(context: any)
	self.context = context
end
function UnitService:Start() end
function UnitService:Register(player: Player, data: any): (any?, string?)
	if
		type(data.Callsign) ~= "string"
		or #data.Callsign < 2
		or #data.Callsign > 16
		or not self.context.Configuration.Departments[data.DepartmentId]
		or not self.context.Configuration.Stations[data.StationId]
	then
		return nil, "INVALID_UNIT"
	end
	local unit = {
		UnitId = tostring(player.UserId),
		UserId = player.UserId,
		Callsign = data.Callsign,
		DepartmentId = data.DepartmentId,
		DivisionId = data.DivisionId,
		StationId = data.StationId,
		Status = "Available",
	}
	self.units[unit.UnitId] = unit
	return unit, nil
end
function UnitService:SetStatus(unitId: string, status: string): (boolean, string?)
	local unit = self.units[unitId]
	if not unit or not table.find(self.context.Configuration.Dispatch.UnitStatuses, status) then
		return false, "INVALID_UNIT_STATUS"
	end
	unit.Status = status
	return true, nil
end
function UnitService:SetCallsign(unitId: string, callsign: string): (boolean, string?)
	local unit = self.units[unitId]
	if not unit then
		return false, "UNIT_NOT_FOUND"
	end
	if type(callsign) ~= "string" or #callsign < 2 or #callsign > 16 then
		return false, "INVALID_CALLSIGN"
	end
	unit.Callsign = callsign
	return true, nil
end
function UnitService:Unregister(player: Player)
	local unitId = tostring(player.UserId)
	-- Hand back any call this unit was working before the unit disappears.
	--
	-- Done here rather than at each call site because this is the single point
	-- every route out passes through: going off duty deliberately, and
	-- PlayerRemoving when somebody disconnects mid-shift.
	local calls = self.context.Services:Get("CallService")
	if calls and calls.ReleaseUnit then
		calls:ReleaseUnit(unitId)
	end
	self.units[unitId] = nil
end
function UnitService:Snapshot(): { any }
	local result = {}
	for _, unit in self.units do
		table.insert(result, table.clone(unit))
	end
	table.sort(result, function(a, b)
		return a.Callsign < b.Callsign
	end)
	return result
end
function UnitService:Destroy()
	table.clear(self.units)
end
return UnitService
