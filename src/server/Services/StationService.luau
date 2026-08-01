--!strict
local StationService = {}
function StationService:Init(context: any)
	self.context = context
end
function StationService:Start() end
function StationService:IsValid(stationId: string, departmentId: string, spawnName: string): boolean
	local station = self.context.Configuration.Stations[stationId]
	return station ~= nil
		and table.find(station.DepartmentIds, departmentId) ~= nil
		and table.find(station.SpawnNames, spawnName) ~= nil
end
function StationService:Destroy() end
return StationService
