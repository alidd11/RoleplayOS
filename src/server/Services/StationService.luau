--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpawnPolicy = require(ReplicatedStorage.RoleplayOS.Shared.SpawnPolicy)
local StationService = {}

function StationService:Init(context: any)
	self.context = context
end

function StationService:Start() end

function StationService:ValidateSpawn(
	stationId: string,
	spawnId: string,
	roleId: string,
	departmentId: string?
): (boolean, string?)
	return SpawnPolicy.validate(
		self.context.Configuration.Stations,
		self.context.Configuration.Spawns,
		stationId,
		spawnId,
		roleId,
		departmentId
	)
end

function StationService:GetAvailableSpawns(roleId: string, departmentId: string?): { any }
	local result = {}
	for spawnId, definition in self.context.Configuration.Spawns do
		local allowed = self:ValidateSpawn(definition.StationId, spawnId, roleId, departmentId)
		if allowed then
			local station = self.context.Configuration.Stations[definition.StationId]
			table.insert(result, {
				SpawnId = spawnId,
				StationId = station.Id,
				StationName = station.Name,
			})
		end
	end
	return result
end

function StationService:Destroy() end

return StationService
