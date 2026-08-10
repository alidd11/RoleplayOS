--!strict

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local VehicleSpawnerService = {
	-- A broken or absent vehicle facility degrades that feature only. It must
	-- never prevent character, data, access, MDT, phone or custody startup.
	Critical = false,
	active = {},
	cooldowns = {},
	spawning = {},
	connections = {},
}

local function rootPosition(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function modelPosition(instance: Instance): Vector3?
	local interaction = instance:FindFirstChild("InteractionPoint", true)
	if interaction and interaction:IsA("BasePart") then
		return interaction.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

function VehicleSpawnerService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.VehicleSpawners
end

function VehicleSpawnerService:_folder(): Instance?
	return Workspace:FindFirstChild(self.settings.FolderName)
end

function VehicleSpawnerService:_spawner(spawnerId: string): Instance?
	local folder = self:_folder()
	if not folder then
		return nil
	end
	for _, instance in folder:GetDescendants() do
		if
			(instance:IsA("Model") or instance:IsA("BasePart"))
			and instance:GetAttribute("SpawnerId") == spawnerId
		then
			return instance
		end
	end
	return nil
end

function VehicleSpawnerService:_authorise(player: Player, spawnerId: string): (Instance?, string?)
	local spawner = self:_spawner(spawnerId)
	if not spawner then
		return nil, "SPAWNER_NOT_FOUND"
	end
	local playerPosition = rootPosition(player)
	local position = modelPosition(spawner)
	if not playerPosition or not position then
		return nil, "CHARACTER_NOT_READY"
	end
	if (playerPosition - position).Magnitude > self.settings.MaximumInteractionDistance then
		return nil, "SPAWNER_TOO_FAR"
	end
	local departmentId = spawner:GetAttribute("DepartmentId")
	if type(departmentId) == "string" and departmentId ~= "" then
		local duty = self.context.Services:Get("DutyService"):Get(player)
		if not duty or duty.DepartmentId ~= departmentId then
			return nil, "WRONG_DEPARTMENT"
		end
		local divisionId = spawner:GetAttribute("DivisionId")
		if type(divisionId) == "string" and divisionId ~= "" and duty.DivisionId ~= divisionId then
			return nil, "WRONG_DIVISION"
		end
	end
	return spawner, nil
end

function VehicleSpawnerService:_definitionAllowed(
	player: Player,
	spawner: Instance,
	definition: any
): boolean
	local departmentId = spawner:GetAttribute("DepartmentId")
	if type(departmentId) == "string" and departmentId ~= "" then
		if definition.Category ~= "Service" or definition.DepartmentId ~= departmentId then
			return false
		end
		local divisionId = spawner:GetAttribute("DivisionId")
		return type(divisionId) ~= "string"
			or divisionId == ""
			or definition.DivisionId == nil
			or definition.DivisionId == divisionId
	end
	if definition.Category ~= "Civilian" then
		return false
	end
	for _, vehicle in self.context.Services:Get("VehicleOwnershipService"):List(player) do
		if vehicle.DefinitionId == definition.Id then
			return true
		end
	end
	return false
end

function VehicleSpawnerService:Menu(player: Player, spawnerId: string): (any?, string?)
	local spawner, reason = self:_authorise(player, spawnerId)
	if not spawner then
		return nil, reason
	end
	local vehicles = {}
	local departmentId = spawner:GetAttribute("DepartmentId")
	if type(departmentId) == "string" and departmentId ~= "" then
		for id, definition in self.context.Configuration.Vehicles do
			local template = self:_template(definition)
			if self:_definitionAllowed(player, spawner, definition) and template then
				table.insert(vehicles, {
					Id = id,
					Name = definition.Name,
					Category = definition.Category,
					DivisionId = definition.DivisionId,
				})
			end
		end
	else
		for _, owned in self.context.Services:Get("VehicleOwnershipService"):List(player) do
			local definition = self.context.Configuration.Vehicles[owned.DefinitionId]
			local template = definition and self:_template(definition)
			if definition and definition.Category == "Civilian" and template then
				table.insert(vehicles, {
					Id = owned.DefinitionId,
					VehicleId = owned.VehicleId,
					Name = definition.Name,
					Category = "Civilian",
					Registration = owned.Registration,
				})
			end
		end
	end
	table.sort(vehicles, function(a, b)
		if a.Name == b.Name then
			return tostring(a.Registration or a.VehicleId or "")
				< tostring(b.Registration or b.VehicleId or "")
		end
		return a.Name < b.Name
	end)
	return {
		SpawnerId = spawnerId,
		Name = spawner:GetAttribute("DisplayName") or spawner.Name,
		Vehicles = vehicles,
	},
		nil
end

function VehicleSpawnerService:AuthoriseCivilianFacility(
	player: Player,
	spawnerId: string
): (boolean, string?)
	local spawner, reason = self:_authorise(player, spawnerId)
	if not spawner then
		return false, reason
	end
	local departmentId = spawner:GetAttribute("DepartmentId")
	if type(departmentId) == "string" and departmentId ~= "" then
		return false, "CIVILIAN_FACILITY_REQUIRED"
	end
	return true, nil
end

function VehicleSpawnerService:_template(definition: any): Model?
	local current: Instance? = ServerStorage:FindFirstChild("RoleplayOSVehicleTemplates")
		or ServerStorage:FindFirstChild("RoleplayOSAssets")
	for _, segment in definition.AssetPath or {} do
		current = current and current:FindFirstChild(segment) or nil
	end
	if current and current:IsA("Model") then
		return current
	end
	-- Never clone a live Workspace vehicle. Its A-Chassis initializer and bundled
	-- scripts have already run, so it is mutable runtime state rather than a
	-- reusable template. New imports must be installed in ServerStorage first.
	return nil
end

function VehicleSpawnerService:_bay(spawner: Instance): (BasePart?, string?)
	local points = spawner:FindFirstChild("SpawnPoints", true)
	if not points then
		return nil, "NO_SPAWN_POINTS"
	end
	for _, point in points:GetChildren() do
		if point:IsA("BasePart") then
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { spawner, point }
			local occupied = false
			for _, part in
				Workspace:GetPartBoundsInBox(point.CFrame, self.settings.SpawnClearance, params)
			do
				local model = part:FindFirstAncestorOfClass("Model")
				if
					model
					and (
						model:FindFirstChildWhichIsA("VehicleSeat", true)
						or model:FindFirstChildWhichIsA("Humanoid", true)
					)
				then
					occupied = true
					break
				end
			end
			if not occupied then
				return point, nil
			end
		end
	end
	return nil, "ALL_BAYS_OCCUPIED"
end

-- Imported vehicles rarely share the same pivot convention. Some use the
-- chassis centre, others the floor, and several have a pivot well outside the
-- visible body. Placing that arbitrary pivot on the bay surface can put the
-- wheels below the map, after which Roblox removes the falling assembly.
-- Position the vehicle by its actual bounding box instead.
function VehicleSpawnerService:_place(vehicle: Model, bay: BasePart)
	local pivot = vehicle:GetPivot()
	local boxCFrame, boxSize = vehicle:GetBoundingBox()
	local pivotToBox = pivot:ToObjectSpace(boxCFrame)
	local targetBox = bay.CFrame * CFrame.new(0, bay.Size.Y / 2 + boxSize.Y / 2 + 0.75, 0)
	vehicle:PivotTo(targetBox * pivotToBox:Inverse())
end

function VehicleSpawnerService:_guardInitialSpawn(vehicle: Model, bay: BasePart)
	local rescued = false
	task.spawn(function()
		local deadline = os.clock() + 10
		while vehicle.Parent and os.clock() < deadline do
			task.wait(0.25)
			local position = vehicle:GetPivot().Position
			-- Recover relative to the bay, before Roblox's FallenPartsDestroyHeight
			-- can delete the assembly. Waiting until the global destroy boundary is
			-- already crossed races the engine and is too late on low maps.
			if position.Y < bay.Position.Y - 18 then
				if rescued then
					self.context.Logger:Error("Spawned vehicle continued falling after recovery", {
						Vehicle = vehicle.Name,
						DefinitionId = vehicle:GetAttribute("RoleplayOSDefinitionId"),
					})
					return
				end
				rescued = true
				self:_place(vehicle, bay)
				self.context.Logger:Warning("Recovered a vehicle that fell through its bay", {
					Vehicle = vehicle.Name,
					DefinitionId = vehicle:GetAttribute("RoleplayOSDefinitionId"),
				})
			end
		end
	end)
end

function VehicleSpawnerService:Spawn(
	player: Player,
	spawnerId: string,
	definitionId: string,
	vehicleId: string?
): (any?, string?)
	local spawner, reason = self:_authorise(player, spawnerId)
	if not spawner then
		return nil, reason
	end
	local definition = self.context.Configuration.Vehicles[definitionId]
	if not definition or not self:_definitionAllowed(player, spawner, definition) then
		return nil, "VEHICLE_NOT_ALLOWED"
	end
	local existing = self.active[player.UserId]
	if os.clock() - (self.cooldowns[player.UserId] or 0) < self.settings.CooldownSeconds then
		return nil, "SPAWN_COOLDOWN"
	end
	if self.spawning[player.UserId] then
		return nil, "SPAWN_IN_PROGRESS"
	end
	local bay, bayReason = self:_bay(spawner)
	if not bay then
		return nil, bayReason
	end
	local template = self:_template(definition)
	if not template then
		return nil, "VEHICLE_TEMPLATE_MISSING"
	end
	local vehicle = template:Clone()
	vehicle.Name = string.format("%s_%d", definition.ModelName or definitionId, player.UserId)
	local ownership = self.context.Services:Get("VehicleOwnershipService")
	local registration: string? = nil
	self.spawning[player.UserId] = true
	if definition.Category == "Service" then
		local issuedRegistration, registrationReason = ownership:GetOrCreateTeamRegistration(
			player,
			tostring(spawner:GetAttribute("DepartmentId") or "Service"),
			definitionId
		)
		if not issuedRegistration then
			self.spawning[player.UserId] = nil
			vehicle:Destroy()
			return nil, registrationReason or "REGISTRATION_UNAVAILABLE"
		end
		registration = issuedRegistration
	else
		for _, owned in ownership:List(player) do
			if owned.DefinitionId == definitionId and owned.VehicleId == vehicleId then
				registration = owned.Registration
				break
			end
		end
		if not registration then
			self.spawning[player.UserId] = nil
			vehicle:Destroy()
			return nil, "VEHICLE_NOT_OWNED"
		end
	end
	if existing and existing.Parent then
		-- The replacement is now fully authorised and has a valid template and
		-- registration. Only at this point is the player's previous car removed,
		-- so a failed spawn can never leave them without their current vehicle.
		existing:Destroy()
		self.active[player.UserId] = nil
	end
	vehicle:SetAttribute("RoleplayOSDefinitionId", definitionId)
	vehicle:SetAttribute("RoleplayOSOwnerUserId", player.UserId)
	-- Custom registrations are changed by persistent vehicle id, not by the
	-- catalogue definition. Without this attribute VehiclePlateService could not
	-- find the live clone, so the saved plate changed while the car in front of
	-- the player kept its old registration until it was spawned again.
	if type(vehicleId) == "string" and vehicleId ~= "" then
		vehicle:SetAttribute("RoleplayOSVehicleId", vehicleId)
	end
	self.context.Services:Get("VehiclePlateService"):Apply(vehicle, registration or "")
	local vehicleSeat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	if vehicleSeat then
		vehicleSeat:SetAttribute("RoleplayOSRegistration", registration or "")
		vehicleSeat:SetAttribute("RoleplayOSOwnerUserId", player.UserId)
	end
	self:_place(vehicle, bay)
	vehicle.Parent = Workspace
	-- ELS is deliberately framework-owned, but adoption was never called by the
	-- only service that creates framework vehicles. The server therefore had no
	-- tag/state to expose and every emergency-light controller correctly reported
	-- that the spawned car had no recognised lights.
	if type(definition.DepartmentId) == "string" then
		self.context.Services:Get("EmergencyLightsService"):Adopt(vehicle, definition.DepartmentId)
	end
	self.context.Services:Get("WorldBudgetService"):Normalise(vehicle)
	-- A-Chassis templates are intentionally authored anchored. Their Initialize
	-- script creates the runtime joints and unanchors the correct assemblies.
	-- Reapplying the template's anchored state after that initializer ran froze or
	-- tore down the newly-created chassis and was a primary disappearance cause.
	self:_guardInitialSpawn(vehicle, bay)
	self.active[player.UserId] = vehicle
	self.cooldowns[player.UserId] = os.clock()
	self.spawning[player.UserId] = nil
	vehicle.Destroying:Once(function()
		if self.active[player.UserId] == vehicle then
			self.active[player.UserId] = nil
		end
	end)
	return {
		DefinitionId = definitionId,
		ModelName = vehicle.Name,
		Registration = registration,
	},
		nil
end

function VehicleSpawnerService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			local vehicle = self.active[player.UserId]
			if vehicle then
				vehicle:Destroy()
			end
			self.active[player.UserId] = nil
			self.cooldowns[player.UserId] = nil
			self.spawning[player.UserId] = nil
		end)
	)
end

function VehicleSpawnerService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, vehicle in self.active do
		if vehicle.Parent then
			vehicle:Destroy()
		end
	end
	table.clear(self.active)
	table.clear(self.spawning)
end

return VehicleSpawnerService
