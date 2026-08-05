--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local VehicleService = {
	activeByUserId = {},
	activeByModel = {},
	cooldowns = {},
	connections = {},
	accumulator = 0,
}

local function worldPosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

local function rootPosition(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

function VehicleService:Init(context: any)
	self.context = context
end

function VehicleService:_configureTerminal(instance: Instance)
	if not instance:IsDescendantOf(workspace) then
		return
	end
	local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		local parent = if instance:IsA("BasePart")
			then instance
			else instance:FindFirstChildWhichIsA("BasePart", true)
		if not parent then
			return
		end
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RoleplayOSVehiclePrompt"
		prompt.Parent = parent
	end
	prompt.ActionText = "Browse vehicles"
	prompt.ObjectText = tostring(instance:GetAttribute("DisplayName") or "Vehicle terminal")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = self.context.Configuration.VehicleSpawning.PromptHoldDuration
	prompt.MaxActivationDistance =
		self.context.Configuration.VehicleSpawning.MaximumInteractionDistance
end

function VehicleService:Start()
	local settings = self.context.Configuration.VehicleSpawning
	for _, terminal in CollectionService:GetTagged(settings.TerminalTag) do
		self:_configureTerminal(terminal)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(settings.TerminalTag):Connect(function(instance)
			self:_configureTerminal(instance)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self:Despawn(player)
			self.cooldowns[player.UserId] = nil
		end)
	)
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(dt)
			self.accumulator += dt
			if self.accumulator < settings.TrackingIntervalSeconds then
				return
			end
			local elapsed = self.accumulator
			self.accumulator = 0
			for userId, active in self.activeByUserId do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					self:_trackVehicle(player, active, elapsed)
				end
			end
		end)
	)
end

function VehicleService:_trackVehicle(player: Player, active: any, elapsed: number)
	local model = active.Model
	if not model.Parent then
		return
	end
	self:_authoriseServiceDriver(active)
	local settings = self.context.Configuration.VehicleSpawning
	local position = model:GetPivot().Position
	local previous = active.LastPosition
	active.LastPosition = position
	if not previous then
		return
	end
	local distanceStuds = (position - previous).Magnitude
	local maximumDistance = settings.MaximumTrackedSpeedStudsPerSecond * elapsed + 12
	if distanceStuds > maximumDistance then
		-- Treat implausible jumps as teleports, not mileage. Vehicle physics can be
		-- client-owned, so persistent economy values never trust an unbounded delta.
		active.TelemetryValid = false
		active.LastSpeedMph = 0
		active.LastSampleAt = os.clock()
		return
	end
	active.TelemetryValid = true
	active.LastSpeedMph = distanceStuds / elapsed * settings.StudsPerSecondToMph
	active.LastSampleAt = os.clock()
	local vehicle = active.Vehicle
	local distanceMiles = distanceStuds * settings.StudsToMiles
	vehicle.Mileage = math.max(0, (vehicle.Mileage or 0) + distanceMiles)
	local seat = active.Seat
	local occupied = seat and seat.Occupant ~= nil
	local idling = occupied and distanceStuds < 0.5
	local fuelUsed = if occupied
		then distanceMiles * settings.FuelPercentPerMile + (if idling
			then settings.IdleFuelPercentPerMinute * elapsed / 60
			else 0)
		else 0
	vehicle.Fuel = math.clamp((vehicle.Fuel or 100) - fuelUsed, 0, 100)
	model:SetAttribute("RoleplayOSMileage", vehicle.Mileage)
	model:SetAttribute("RoleplayOSFuel", vehicle.Fuel)
	model:SetAttribute("RoleplayOSFuelEmpty", vehicle.Fuel <= 0)
	active.Summary.Mileage = vehicle.Mileage
	active.Summary.Fuel = vehicle.Fuel
	if seat then
		seat:SetAttribute("RoleplayOSFuel", vehicle.Fuel)
		if settings.StopVehicleWhenFuelEmpty and vehicle.Fuel <= 0 then
			if seat:GetAttribute("RoleplayOSOriginalMaxSpeed") == nil then
				seat:SetAttribute("RoleplayOSOriginalMaxSpeed", seat.MaxSpeed)
			end
			seat.MaxSpeed = 0
		elseif vehicle.Fuel > 0 then
			local original = seat:GetAttribute("RoleplayOSOriginalMaxSpeed")
			if type(original) == "number" then
				seat.MaxSpeed = original
				seat:SetAttribute("RoleplayOSOriginalMaxSpeed", nil)
			end
		end
	end
	if not active.IsTeam then
		active.Unsaved = true
		local now = os.clock()
		if now - active.LastPersistedAt >= settings.PersistenceIntervalSeconds then
			self.context.Services:Get("DataService"):MarkDirty(player)
			active.LastPersistedAt = now
			active.Unsaved = false
		end
	end
end

function VehicleService:GetTelemetry(model: Model): any?
	local active = self.activeByModel[model]
	if not active or not active.TelemetryValid then
		return nil
	end
	local maximumAge = self.context.Configuration.VehicleSpawning.TrackingIntervalSeconds * 2.5
	if os.clock() - active.LastSampleAt > maximumAge then
		return nil
	end
	return {
		SpeedMph = active.LastSpeedMph,
		SampledAt = active.LastSampleAt,
	}
end

function VehicleService:_terminal(player: Player, terminalId: string): (Instance?, string?)
	local settings = self.context.Configuration.VehicleSpawning
	local playerPosition = rootPosition(player)
	if not playerPosition then
		return nil, "CHARACTER_NOT_ACTIVE"
	end
	for _, terminal in CollectionService:GetTagged(settings.TerminalTag) do
		if
			terminal:GetAttribute("TerminalId") == terminalId and terminal:IsDescendantOf(workspace)
		then
			local position = worldPosition(terminal)
			if
				position
				and (position - playerPosition).Magnitude <= settings.MaximumInteractionDistance
			then
				return terminal, nil
			end
			return nil, "TERMINAL_TOO_FAR"
		end
	end
	return nil, "TERMINAL_NOT_FOUND"
end

function VehicleService:_terminalScope(terminal: Instance): (any?, string?)
	local dealershipId = terminal:GetAttribute("DealershipId")
	if type(dealershipId) == "string" and self.context.Configuration.Dealerships[dealershipId] then
		return { Kind = "Civilian", DealershipId = dealershipId }, nil
	end
	local departmentId = terminal:GetAttribute("DepartmentId")
	if type(departmentId) == "string" and self.context.Configuration.Departments[departmentId] then
		local divisionId = terminal:GetAttribute("DivisionId")
		if
			divisionId ~= nil
			and (
				type(divisionId) ~= "string"
				or not self.context.Configuration.Divisions[divisionId]
				or self.context.Configuration.Divisions[divisionId].DepartmentId ~= departmentId
			)
		then
			return nil, "TERMINAL_DIVISION_INVALID"
		end
		return {
			Kind = "Service",
			DepartmentId = departmentId,
			DivisionId = divisionId,
		},
			nil
	end
	return nil, "TERMINAL_SCOPE_REQUIRED"
end

function VehicleService:AuthoriseDealershipTerminal(
	player: Player,
	terminalId: string
): (any?, string?)
	local terminal, reason = self:_terminal(player, terminalId)
	if not terminal then
		return nil, reason
	end
	local scope, scopeReason = self:_terminalScope(terminal)
	if not scope or scope.Kind ~= "Civilian" or not scope.DealershipId then
		return nil, scopeReason or "DEALERSHIP_TERMINAL_REQUIRED"
	end
	return scope, nil
end

function VehicleService:_definitionMatchesTerminal(definition: any, scope: any): boolean
	if scope.Kind ~= "Service" or definition.DepartmentId ~= scope.DepartmentId then
		return false
	end
	if type(scope.DivisionId) == "string" then
		return definition.DivisionId == scope.DivisionId
	end
	return true
end

function VehicleService:_spawnPoint(terminal: Instance, terminalId: string): (BasePart?, string?)
	local settings = self.context.Configuration.VehicleSpawning
	local terminalPosition = worldPosition(terminal)
	if not terminalPosition then
		return nil, "TERMINAL_NOT_FOUND"
	end
	local candidates = {}
	for _, point in CollectionService:GetTagged(settings.SpawnPointTag) do
		if
			point:IsA("BasePart")
			and point:IsDescendantOf(workspace)
			and point:GetAttribute("TerminalId") == terminalId
			and (point.Position - terminalPosition).Magnitude <= settings.MaximumSpawnDistance
		then
			table.insert(candidates, point)
		end
	end
	table.sort(candidates, function(a, b)
		return (a.Position - terminalPosition).Magnitude < (b.Position - terminalPosition).Magnitude
	end)
	local clearance = settings.SpawnClearance
	for _, point in candidates do
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { point }
		local occupied = false
		for _, part in
			workspace:GetPartBoundsInBox(
				point.CFrame,
				Vector3.new(clearance[1], clearance[2], clearance[3]),
				params
			)
		do
			local model = part:FindFirstAncestorOfClass("Model")
			if
				model
				and (
					model:GetAttribute("RoleplayOSVehicleId") ~= nil
					or model:FindFirstChildWhichIsA("Humanoid") ~= nil
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
	return nil, if #candidates == 0 then "SPAWN_POINT_UNAVAILABLE" else "SPAWN_POINT_OCCUPIED"
end

function VehicleService:_serviceAccess(player: Player, definition: any): (boolean, string?)
	local duty = self.context.Services:Get("DutyService"):Get(player)
	if
		not duty
		or not player.Team
		or player.Team ~= self.context.Services:Get("TeamService"):Get(definition.TeamName)
		or duty.DepartmentId ~= definition.DepartmentId
		or not table.find(definition.RoleIds or {}, duty.RoleId)
	then
		return false, "TEAM_VEHICLE_NOT_AUTHORISED"
	end
	local access = self.context.Services:Get("AccessService"):Evaluate(player, definition.Access)
	return access.Allowed, if access.Allowed then nil else access.ReasonCode
end

function VehicleService:_authoriseServiceDriver(active: any)
	if not active.IsTeam then
		return
	end
	local seat = active.Seat
	local humanoid = seat and seat.Occupant
	if not humanoid then
		return
	end
	local character = humanoid.Parent
	local driver = if character and character:IsA("Model")
		then Players:GetPlayerFromCharacter(character)
		else nil
	local allowed = driver and select(1, self:_serviceAccess(driver, active.Definition)) or false
	if allowed then
		return
	end
	humanoid.Sit = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

function VehicleService:_disconnectActive(active: any)
	for _, connection in active.Connections or {} do
		connection:Disconnect()
	end
	table.clear(active.Connections or {})
end

function VehicleService:Menu(player: Player, terminalId: string): (any?, string?)
	local terminal, reason = self:_terminal(player, terminalId)
	if not terminal then
		return nil, reason
	end
	local scope, scopeReason = self:_terminalScope(terminal)
	if not scope then
		return nil, scopeReason
	end
	local dealershipId = scope.DealershipId
	local dealership = if type(dealershipId) == "string"
		then self.context.Configuration.Dealerships[dealershipId]
		else nil
	local owned = if scope.Kind == "Civilian"
		then self.context.Services:Get("VehicleOwnershipService"):List(player)
		else {}
	local active = self.activeByUserId[player.UserId]
	for _, vehicle in owned do
		vehicle.Available = active == nil
	end
	local serviceVehicles = {}
	for definitionId, definition in self.context.Configuration.Vehicles do
		if
			definition.Category == "Service"
			and self:_definitionMatchesTerminal(definition, scope)
		then
			local allowed, accessReason = self:_serviceAccess(player, definition)
			if allowed or definition.Access.DisplayWhenLocked == true then
				table.insert(serviceVehicles, {
					DefinitionId = definitionId,
					Name = definition.Name,
					Category = "Service",
					Available = allowed and active == nil,
					LockedReason = if allowed then nil else accessReason,
				})
			end
		end
	end
	table.sort(serviceVehicles, function(a, b)
		return a.Name < b.Name
	end)
	return {
		Terminal = {
			Id = terminalId,
			Name = if dealership then dealership.Name else "Vehicle garage",
			DealershipId = dealershipId,
			Kind = scope.Kind,
			DepartmentId = scope.DepartmentId,
			DivisionId = scope.DivisionId,
		},
		OwnedVehicles = owned,
		ServiceVehicles = serviceVehicles,
		ActiveVehicle = active and active.Summary or nil,
	},
		nil
end

function VehicleService:_template(definition: any): Model?
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	local models = assets and assets:FindFirstChild("Vehicles")
	local template: Instance? = assets
	if type(definition.AssetPath) == "table" then
		for _, segment in definition.AssetPath do
			template = template and template:FindFirstChild(segment) or nil
		end
	else
		template = models and models:FindFirstChild(definition.ModelName)
	end
	if not template and models then
		template = models:FindFirstChild(definition.ModelName)
	end
	return if template and template:IsA("Model") then template else nil
end

function VehicleService:_spawn(
	player: Player,
	vehicle: any,
	definition: any,
	spawnPart: BasePart,
	isTeam: boolean
): (any?, string?)
	if self.activeByUserId[player.UserId] then
		return nil, "ACTIVE_VEHICLE_EXISTS"
	end
	local lastSpawn = self.cooldowns[player.UserId] or 0
	if os.clock() - lastSpawn < self.context.Configuration.VehicleSpawning.SpawnCooldownSeconds then
		return nil, "SPAWN_COOLDOWN"
	end
	local template = self:_template(definition)
	if not template then
		return nil, "VEHICLE_MODEL_UNAVAILABLE"
	end
	local model = template:Clone()
	model:PivotTo(spawnPart.CFrame)
	self:_applyIdentity(model, vehicle, player.UserId)
	vehicle.Mileage = math.max(0, vehicle.Mileage or 0)
	vehicle.Fuel = math.clamp(vehicle.Fuel or 100, 0, 100)
	model:SetAttribute("RoleplayOSMileage", vehicle.Mileage)
	model:SetAttribute("RoleplayOSFuel", vehicle.Fuel)
	model:SetAttribute("RoleplayOSFuelEmpty", vehicle.Fuel <= 0)
	if isTeam then
		model:SetAttribute("RoleplayOSTeamVehicle", true)
		model:SetAttribute("RoleplayOSTeamName", definition.TeamName)
	end
	model.Parent = workspace
	local summary = {
		VehicleId = vehicle.VehicleId,
		DefinitionId = definition.Id,
		Registration = vehicle.Registration,
		TeamVehicle = isTeam,
		Mileage = vehicle.Mileage,
		Fuel = vehicle.Fuel,
	}
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat then
		seat:SetAttribute("RoleplayOSRegistration", vehicle.Registration)
		seat:SetAttribute("RoleplayOSFuel", vehicle.Fuel)
		if
			self.context.Configuration.VehicleSpawning.StopVehicleWhenFuelEmpty
			and vehicle.Fuel <= 0
		then
			seat:SetAttribute("RoleplayOSOriginalMaxSpeed", seat.MaxSpeed)
			seat.MaxSpeed = 0
		end
	end
	local active = {
		Model = model,
		Summary = summary,
		Vehicle = vehicle,
		Definition = definition,
		Seat = seat,
		IsTeam = isTeam,
		Connections = {},
		LastPosition = model:GetPivot().Position,
		LastPersistedAt = os.clock(),
		Unsaved = false,
		TelemetryValid = false,
		LastSpeedMph = 0,
		LastSampleAt = 0,
	}
	self.activeByUserId[player.UserId] = active
	self.activeByModel[model] = active
	self.cooldowns[player.UserId] = os.clock()
	table.insert(
		active.Connections,
		model.AncestryChanged:Connect(function(_, parent)
			local current = self.activeByUserId[player.UserId]
			if parent == nil and current and current.Model == model then
				self:_disconnectActive(current)
				self.activeByUserId[player.UserId] = nil
				self.activeByModel[model] = nil
			end
		end)
	)
	if isTeam and seat then
		table.insert(
			active.Connections,
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				task.defer(function()
					if model.Parent then
						self:_authoriseServiceDriver(active)
					end
				end)
			end)
		)
		self:_authoriseServiceDriver(active)
	end
	return summary, nil
end

function VehicleService:SpawnOwned(
	player: Player,
	terminalId: string,
	vehicleId: string
): (any?, string?)
	local terminal, reason = self:_terminal(player, terminalId)
	if not terminal then
		return nil, reason
	end
	local scope, scopeReason = self:_terminalScope(terminal)
	if not scope or scope.Kind ~= "Civilian" then
		return nil, scopeReason or "CIVILIAN_TERMINAL_REQUIRED"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
	if not character then
		return nil, "CHARACTER_NOT_ACTIVE"
	end
	local owned
	for _, vehicle in character.Vehicles do
		if vehicle.VehicleId == vehicleId then
			owned = vehicle
			break
		end
	end
	if not owned then
		return nil, "VEHICLE_NOT_OWNED"
	end
	local definition = self.context.Configuration.Vehicles[owned.DefinitionId]
	if not definition or definition.Category == "Service" then
		return nil, "VEHICLE_NOT_OWNED"
	end
	local spawnPoint, spawnReason = self:_spawnPoint(terminal, terminalId)
	if not spawnPoint then
		return nil, spawnReason
	end
	return self:_spawn(player, owned, definition, spawnPoint, false)
end

function VehicleService:SpawnService(
	player: Player,
	terminalId: string,
	definitionId: string
): (any?, string?)
	local terminal, reason = self:_terminal(player, terminalId)
	if not terminal then
		return nil, reason
	end
	local scope, scopeReason = self:_terminalScope(terminal)
	if not scope or scope.Kind ~= "Service" then
		return nil, scopeReason or "SERVICE_TERMINAL_REQUIRED"
	end
	local definition = self.context.Configuration.Vehicles[definitionId]
	if not definition or definition.Category ~= "Service" then
		return nil, "TEAM_VEHICLE_NOT_AUTHORISED"
	end
	if not self:_definitionMatchesTerminal(definition, scope) then
		return nil, "VEHICLE_NOT_AVAILABLE_AT_TERMINAL"
	end
	local allowed, accessReason = self:_serviceAccess(player, definition)
	if not allowed then
		return nil, accessReason
	end
	local spawnPoint, spawnReason = self:_spawnPoint(terminal, terminalId)
	if not spawnPoint then
		return nil, spawnReason
	end
	local registration, registrationReason = self.context.Services
		:Get("VehicleOwnershipService")
		:GetOrCreateTeamRegistration(player, definition.TeamName, definitionId)
	if not registration then
		return nil, registrationReason
	end
	local vehicle = {
		VehicleId = string.format(
			"TEAM:%d:%s:%s",
			player.UserId,
			definition.TeamName,
			definitionId
		),
		Registration = registration,
		OwnerCharacterId = nil,
		Mileage = 0,
		Fuel = 100,
	}
	return self:_spawn(player, vehicle, definition, spawnPoint, true)
end

function VehicleService:Despawn(player: Player)
	local current = self.activeByUserId[player.UserId]
	self.activeByUserId[player.UserId] = nil
	if current then
		self:_disconnectActive(current)
		self.activeByModel[current.Model] = nil
	end
	if current and current.Unsaved and not current.IsTeam then
		self.context.Services:Get("DataService"):MarkDirty(player)
	end
	if current and current.Model.Parent then
		current.Model:Destroy()
	end
end

function VehicleService:_plate(part: BasePart, registration: string)
	local gui = part:FindFirstChild("RoleplayOSRegistration")
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "RoleplayOSRegistration"
		gui.Face = Enum.NormalId.Front
		gui.PixelsPerStud = 80
		gui.Parent = part
		local text = Instance.new("TextLabel")
		text.Name = "Registration"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Color3.fromRGB(244, 204, 45)
		text.BorderSizePixel = 0
		text.Font = Enum.Font.RobotoMono
		text.TextColor3 = Color3.fromRGB(12, 15, 18)
		text.TextScaled = true
		text.Parent = gui
	end
	local label = gui:FindFirstChild("Registration")
	if label and label:IsA("TextLabel") then
		label.Text = registration
	end
end

function VehicleService:_applyIdentity(model: Model, vehicle: any, ownerUserId: number)
	model:SetAttribute("RoleplayOSVehicleId", vehicle.VehicleId)
	model:SetAttribute("RoleplayOSRegistration", vehicle.Registration)
	model:SetAttribute("RoleplayOSOwnerUserId", ownerUserId)
	model:SetAttribute("RoleplayOSOwnerCharacterId", vehicle.OwnerCharacterId)
	local matched = false
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and table.find(
				self.context.Configuration.VehicleIdentity.PlatePartNames,
				descendant.Name
			)
		then
			matched = true
			self:_plate(descendant, vehicle.Registration)
		end
	end
	if matched then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		return
	end
	local _, size = model:GetBoundingBox()
	for _, direction in { -1, 1 } do
		local plate = Instance.new("Part")
		plate.Name = "RegistrationPlate"
		plate.Size = Vector3.new(2.4, 0.55, 0.08)
		plate.CanCollide = false
		plate.Massless = true
		plate.CFrame = root.CFrame
			* CFrame.new(0, -size.Y * 0.25, direction * size.Z * 0.5)
			* CFrame.Angles(0, if direction == 1 then math.pi else 0, 0)
		plate.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = plate
		weld.Parent = plate
		self:_plate(plate, vehicle.Registration)
	end
end

function VehicleService:Destroy()
	for userId, current in self.activeByUserId do
		local player = Players:GetPlayerByUserId(userId)
		if player and current.Unsaved and not current.IsTeam then
			self.context.Services:Get("DataService"):MarkDirty(player)
		end
		self:_disconnectActive(current)
		current.Model:Destroy()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.activeByUserId)
	table.clear(self.activeByModel)
	table.clear(self.cooldowns)
end

return VehicleService
