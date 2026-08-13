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
	-- Held per player and released when they leave, rather than appended to the
	-- flat list above, so a long server does not accumulate one closure per
	-- person who has ever played on it.
	deathConnections = {},
	spawnConnections = {},
	seatConnections = {},
}

function VehicleSpawnerService:_vehicleDefinitions(): { [string]: any }
	local validator = self.context.Services:Get("ContentValidationService")
	if validator and validator.GetVehicleDefinitions then
		return validator:GetVehicleDefinitions()
	end
	return self.context.Configuration.Vehicles
end

function VehicleSpawnerService:_vehicleDefinition(definitionId: string): any?
	local validator = self.context.Services:Get("ContentValidationService")
	if validator and validator.GetVehicleDefinition then
		return validator:GetVehicleDefinition(definitionId)
	end
	return self.context.Configuration.Vehicles[definitionId]
end

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

-- Stands anybody up before their seat stops existing.
--
-- A passenger left seated when the model is destroyed keeps the sitting state
-- with no seat beneath them: they float, cannot walk, and have to reset. That
-- applies to every route a vehicle disappears by, not only to the owner dying,
-- so it is done wherever one is destroyed.
local function ejectOccupants(vehicle: Instance)
	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			local occupant = descendant.Occupant
			if occupant then
				occupant.Sit = false
				occupant:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
end

-- Cuts anything the vehicle tied the rider to when they get off it.
--
-- Bike kits pose their rider by welding limbs to the machine, which is how the
-- riding position survives with no animation playing, and several of them never
-- undo it. The rider then walks away still joined to a bike that is no longer
-- moving with them: accessories hang off the head, limbs trail behind, and the
-- character reads as having come apart. Nothing is wrong with the avatar itself
-- -- it looks correct until the moment it is first mounted -- so the damage is
-- entirely in joints somebody else's script left behind.
--
-- Only joints with one end in the rider and the other in the vehicle are cut.
-- That is exactly the set the vehicle added and nothing else: the rig's own
-- joints have both ends in the character, and a held tool's weld does too, since
-- an equipped tool is parented into the character. Both sides are searched
-- because a kit may parent its welds to either.
local function detachRider(character: Model, vehicle: Instance): number
	local function inside(part: Instance?, root: Instance): boolean
		return part ~= nil and (part == root or part:IsDescendantOf(root))
	end
	local removed = 0
	for _, container in { character, vehicle } do
		for _, descendant in container:GetDescendants() do
			if
				not (
					descendant:IsA("Weld")
					or descendant:IsA("WeldConstraint")
					or descendant:IsA("Motor6D")
				)
			then
				continue
			end
			local joint = descendant :: any
			local first, second = joint.Part0, joint.Part1
			local firstInRider = inside(first, character)
			local secondInRider = inside(second, character)
			if
				(firstInRider and inside(second, vehicle))
				or (secondInRider and inside(first, vehicle))
			then
				descendant:Destroy()
				removed += 1
			end
		end
	end
	return removed
end

-- The vehicle a seat belongs to: the outermost model it sits inside.
local function vehicleOf(seat: BasePart): Instance
	local root: Instance = seat
	while root.Parent and root.Parent ~= Workspace do
		root = root.Parent
	end
	return root
end

local function seatPlayer(player: Player, seat: VehicleSeat)
	task.spawn(function()
		for _ = 1, 12 do
			if not seat.Parent or seat.Occupant then
				return
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and root:IsA("BasePart") then
				root.CFrame = seat.CFrame * CFrame.new(0, 2.5, 0)
				task.wait()
				if seat.Parent and not seat.Occupant and humanoid.Parent then
					seat:Sit(humanoid)
				end
				if seat.Occupant == humanoid then
					return
				end
			end
			task.wait(0.25)
		end
	end)
end

-- Imported vehicle kits often bundle optional plugins for a different model
-- hierarchy. Running those plugins against a model without their expected
-- Body.Brakes, Body.Kickstand, SirenControl or sound nodes produces a tight
-- error loop and can consume several gigabytes over a session. The chassis,
-- seat, animation and native plate systems are deliberately left untouched.
local function removePath(root: Instance, path: { string }): boolean
	local current = root
	for index, segment in path do
		local child = current:FindFirstChild(segment)
		if not child then
			return false
		end
		if index == #path then
			child:Destroy()
			return true
		end
		current = child
	end
	return false
end

local function sanitiseImportedVehicle(vehicle: Model)
	local removed = 0
	local function remove(path: { string })
		if removePath(vehicle, path) then
			removed += 1
		end
	end

	-- Honda ADV/NCT optional plugins. The README says these are independent
	-- plugins; this particular model does not provide their required nodes.
	for _, path in
		{
			{ "Tuner", "Plugins", "Kickstand" },
			{ "Tuner", "Plugins", "LightAddon" },
			{ "Tuner", "Plugins", "AC6C_Style_Gauges" },
			{ "Tuner", "Plugins", "AC6_Sounds" },
			{ "Tuner", "Plugins", "EPICLIGHTS_V4" },
		}
	do
		remove(path)
	end

	-- Corolla optional legacy controls. Taxi lighting and sound are not sirens,
	-- and the framework owns the vehicle UI and emergency-lighting boundary.
	for _, path in
		{
			{ "DriveSeat", "Pickup" },
			{ "DriveSeat", "SirenControl" },
			{ "SmeersLightsHandler" },
			{ "AC6_FE_Sounds" },
		}
	do
		remove(path)
	end

	-- Remove known inaccessible Creator Store sounds. Empty/invalid audio must
	-- not be allowed to throw repeatedly from imported handlers.
	local blocked = {
		["10652911149"] = true,
		["10652911247"] = true,
		["11503290062"] = true,
		["370689846"] = true,
	}
	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("Sound") then
			local id = string.match(descendant.SoundId, "%d+")
			if id and blocked[id] then
				descendant:Destroy()
				removed += 1
			end
		end
	end
	if removed > 0 then
		vehicle:SetAttribute("RoleplayOSSafelyAdapted", true)
	end
end

-- Removes the player's vehicle, whatever the reason.
function VehicleSpawnerService:Remove(userId: number)
	local vehicle = self.active[userId]
	self.active[userId] = nil
	if vehicle and vehicle.Parent then
		ejectOccupants(vehicle)
		vehicle:Destroy()
	end
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
		-- Taxi shifts are civilian employment, not a Transport duty profile.
		-- They still use the Transport depot, so authorise them through the
		-- employment credential before applying department-duty checks.
		if
			departmentId == "Transport"
			and self.context.Services:Get("TaxiService"):IsDriver(player)
		then
			return spawner, nil
		end
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
		-- Taxi is a public employment vehicle, but its operational bay belongs
		-- to Transport. Keep the Corolla civilian-owned/free while allowing an
		-- on-shift taxi driver to use the shared Transport fleet facility.
		if departmentId == "Transport" and definition.JobId == "TaxiDriver" then
			return definition.Fleet == true
				and self.context.Services:Get("TaxiService"):IsDriver(player)
		end
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
		return definition.Fleet == true
	end
	if definition.Fleet == true and definition.JobId == "TaxiDriver" then
		return self.context.Services:Get("TaxiService"):IsDriver(player)
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
		for id, definition in self:_vehicleDefinitions() do
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
			local definition = self:_vehicleDefinition(owned.DefinitionId)
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
	local definition = self:_vehicleDefinition(definitionId)
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
	sanitiseImportedVehicle(vehicle)
	local ownership = self.context.Services:Get("VehicleOwnershipService")
	local registration: string? = nil
	self.spawning[player.UserId] = true
	if definition.Category == "Service" or definition.Fleet == true then
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
		ejectOccupants(existing)
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
	if vehicleSeat then
		seatPlayer(player, vehicleSeat)
	end
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

-- Watches one player's seat, and cleans up after whatever they were riding.
function VehicleSpawnerService:_watchSeat(player: Player)
	local previous = self.seatConnections[player.UserId]
	if previous then
		previous:Disconnect()
		self.seatConnections[player.UserId] = nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local lastVehicle: Instance? = nil
	self.seatConnections[player.UserId] = humanoid
		:GetPropertyChangedSignal("SeatPart")
		:Connect(function()
			local seat = humanoid.SeatPart
			if seat then
				lastVehicle = vehicleOf(seat)
				return
			end
			-- Just got off. Deferred by a frame so Roblox has finished removing
			-- its own seat weld before we look at what is left.
			local vehicle = lastVehicle
			lastVehicle = nil
			if not vehicle or not vehicle.Parent then
				return
			end
			task.defer(function()
				local body = player.Character
				if not body or not vehicle.Parent then
					return
				end
				local removed = detachRider(body, vehicle)
				if removed > 0 then
					self.context.Logger:Info("Rider detached from a vehicle that kept hold", {
						UserId = player.UserId,
						Vehicle = vehicle.Name,
						JointsRemoved = removed,
					})
				end
			end)
		end)
end

function VehicleSpawnerService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self:Remove(player.UserId)
			self.cooldowns[player.UserId] = nil
			self.spawning[player.UserId] = nil
			for _, held in { self.deathConnections, self.spawnConnections, self.seatConnections } do
				local connection = held[player.UserId]
				if connection then
					connection:Disconnect()
					held[player.UserId] = nil
				end
			end
		end)
	)
	-- The car goes when its driver does.
	--
	-- Nothing on this server reacted to a player dying, so a dead player's
	-- vehicle stayed in the world until they left it. Spawning again replaces
	-- it, so it was litter rather than a lock-out, but on a full server that is
	-- an abandoned car with physics and lights running for every death.
	--
	-- Died rather than CharacterRemoving, because a character is also removed
	-- for a team change or a manual respawn, and taking somebody's car for those
	-- is a broader rule than the one asked for. Re-armed on every character,
	-- since each respawn brings a new humanoid and a watch connected once at
	-- join stops firing the moment they first die.
	local function watchDeath(player: Player, character: Model)
		local found = character:FindFirstChildWhichIsA("Humanoid")
			or character:WaitForChild("Humanoid", 10)
		if not found or not found:IsA("Humanoid") or player.Character ~= character then
			return
		end
		local previous = self.deathConnections[player.UserId]
		if previous then
			previous:Disconnect()
		end
		self.deathConnections[player.UserId] = found.Died:Connect(function()
			self:Remove(player.UserId)
		end)
	end
	local function watch(player: Player)
		local previous = self.spawnConnections[player.UserId]
		if previous then
			previous:Disconnect()
		end
		self.spawnConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
			watchDeath(player, character)
			-- Re-armed per character: the humanoid is a new instance after every
			-- respawn, so a watcher bound to the old one is watching nothing.
			self:_watchSeat(player)
		end)
		local character = player.Character
		if character then
			task.defer(function()
				if player.Parent and player.Character == character then
					watchDeath(player, character)
					self:_watchSeat(player)
				end
			end)
		end
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function VehicleSpawnerService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, vehicle in self.active do
		if vehicle.Parent then
			ejectOccupants(vehicle)
			vehicle:Destroy()
		end
	end
	for _, held in { self.deathConnections, self.spawnConnections } do
		for _, connection in held do
			connection:Disconnect()
		end
		table.clear(held)
	end
	table.clear(self.active)
	table.clear(self.spawning)
end

return VehicleSpawnerService
