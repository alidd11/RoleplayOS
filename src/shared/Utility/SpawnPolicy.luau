--!strict

local SpawnPolicy = {}

function SpawnPolicy.validate(
	stations: any,
	spawns: any,
	stationId: string,
	spawnId: string,
	roleId: string,
	departmentId: string?
): (boolean, string?)
	local station = stations[stationId]
	local spawn = spawns[spawnId]
	if not station or not spawn or spawn.StationId ~= stationId then
		return false, "SPAWN_NOT_AT_STATION"
	end
	if not table.find(station.SpawnIds, spawnId) then
		return false, "SPAWN_NOT_AT_STATION"
	end
	if not table.find(spawn.RoleIds, roleId) then
		return false, "SPAWN_ROLE_NOT_ALLOWED"
	end
	if departmentId then
		if not table.find(station.DepartmentIds, departmentId) then
			return false, "STATION_DEPARTMENT_NOT_ALLOWED"
		end
		if not table.find(spawn.DepartmentIds, departmentId) then
			return false, "SPAWN_DEPARTMENT_NOT_ALLOWED"
		end
	end
	return true, nil
end

return table.freeze(SpawnPolicy)
