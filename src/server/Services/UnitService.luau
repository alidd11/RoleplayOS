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
function UnitService:Unregister(player: Player)
	self.units[tostring(player.UserId)] = nil
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
