--!strict

local SpawnService = { points = {}, reservations = {} }
local SPAWN_HEIGHT = 4
local RESERVATION_SECONDS = 3
local OFFSETS = {
	Vector3.zero,
	Vector3.new(4, 0, 0),
	Vector3.new(-4, 0, 0),
	Vector3.new(0, 0, 4),
	Vector3.new(0, 0, -4),
}

function SpawnService:Init(context: any)
	self.context = context
end

function SpawnService:_registerConfiguredPoints()
	table.clear(self.points)
	for spawnId, definition in self.context.Configuration.Spawns do
		local matches = {}
		for _, instance in workspace:GetDescendants() do
			if instance.Name == definition.PartName and instance:IsA("BasePart") then
				table.insert(matches, instance)
			end
		end
		if #matches == 1 then
			self.points[spawnId] = matches[1]
		elseif #matches == 0 then
			self.context.Logger:Warning("Configured spawn point is missing", {
				SpawnId = spawnId,
				PartName = definition.PartName,
			})
		else
			self.context.Logger:Error("Configured spawn point is duplicated", {
				SpawnId = spawnId,
				PartName = definition.PartName,
				Count = #matches,
			})
		end
	end
end

function SpawnService:Start()
	self:_registerConfiguredPoints()
end

function SpawnService:Resolve(request: any): (BasePart?, string?)
	local role = self.context.Configuration.Roles[request.RoleId]
	if not role then
		return nil, "ROLE_NOT_FOUND"
	end
	local valid, reason =
		self.context.Services
			:Get("StationService")
			:ValidateSpawn(request.StationId, request.SpawnId, request.RoleId, role.DepartmentId)
	if not valid then
		return nil, reason
	end
	local point = self.points[request.SpawnId]
	if not point or not point:IsDescendantOf(workspace) then
		return nil, "SPAWN_POINT_UNAVAILABLE"
	end
	return point, nil
end

function SpawnService:_reserve(spawnId: string): Vector3
	local now = os.clock()
	local reservations = self.reservations[spawnId] or {}
	local active = {}
	for _, expiresAt in reservations do
		if expiresAt > now then
			table.insert(active, expiresAt)
		end
	end
	table.insert(active, now + RESERVATION_SECONDS)
	self.reservations[spawnId] = active
	return OFFSETS[((#active - 1) % #OFFSETS) + 1]
end

function SpawnService:Spawn(player: Player, request: any): (boolean, string?)
	local point, reason = self:Resolve(request)
	if not point then
		return false, reason
	end
	local offset = self:_reserve(request.SpawnId)
	if point:IsA("SpawnLocation") then
		player.RespawnLocation = point
	else
		player.RespawnLocation = nil
	end
	player:LoadCharacter()
	local deadline = os.clock() + 10
	local character = player.Character
	while not character and os.clock() < deadline do
		task.wait(0.05)
		character = player.Character
	end
	if not character then
		return false, "CHARACTER_SPAWN_TIMEOUT"
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return false, "CHARACTER_ROOT_UNAVAILABLE"
	end
	character:PivotTo(point.CFrame * CFrame.new(offset + Vector3.new(0, SPAWN_HEIGHT, 0)))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	self.context.Logger:Info("Player spawned at registered point", {
		UserId = player.UserId,
		SpawnId = request.SpawnId,
		StationId = request.StationId,
		RoleId = request.RoleId,
	})
	return true, nil
end

function SpawnService:Destroy()
	table.clear(self.points)
	table.clear(self.reservations)
end

return SpawnService
