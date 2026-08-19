--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local RigMechanics = require(script.Parent.RigMechanics)

return function(VehicleSpawnerService)
	function VehicleSpawnerService:_template(definition: any): Model?
		local current: Instance? = ServerStorage:FindFirstChild("RoleplayOSAssets")
		-- Keep the former root as a development migration fallback only. Production
		-- must resolve from the canonical asset tree that real-baseplate.project.json
		-- owns and the deployment validator checks.
		if not current and self.context.Configuration.Framework.Environment ~= "Production" then
			current = ServerStorage:FindFirstChild("RoleplayOSVehicleTemplates")
		end
		for _, segment in definition.AssetPath or {} do
			current = current and current:FindFirstChild(segment) or nil
		end
		if current and current:IsA("Model") then
			return current
		end
		-- Development places may use parked authoring vehicles directly. This is
		-- deliberately unavailable in Production: a live Workspace chassis may
		-- already have initialised and must never become a reusable server template.
		if self.context.Configuration.Framework.Environment ~= "Production" then
			local source: Instance? = Workspace
			if type(definition.WorkspaceSourcePath) == "table" then
				for _, segment in definition.WorkspaceSourcePath do
					source = source and source:FindFirstChild(segment) or nil
				end
			else
				local sourceName = definition.WorkspaceModelName
				source = if type(sourceName) == "string" and sourceName ~= ""
					then Workspace:FindFirstChild(sourceName)
					else nil
			end
			if source and source:IsA("Model") then
				return source
			end
		end
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
						self.context.Logger:Error(
							"Spawned vehicle continued falling after recovery",
							{
								Vehicle = vehicle.Name,
								DefinitionId = vehicle:GetAttribute("RoleplayOSDefinitionId"),
							}
						)
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
		RigMechanics.sanitiseImportedVehicle(vehicle)
		local ownership = self.context.Services:Get("VehicleOwnershipService")
		local registration: string? = nil
		self.spawning[player.UserId] = true
		if definition.Category == "Service" or definition.Fleet == true then
			-- A gang facility has no DepartmentId, so its own fleet plates would
			-- otherwise file under the literal fallback "Service" alongside every
			-- other department-less Fleet vehicle. TerritoryId is what actually
			-- names this facility when DepartmentId does not.
			local teamName = spawner:GetAttribute("DepartmentId")
				or spawner:GetAttribute("TerritoryId")
				or "Service"
			local issuedRegistration, registrationReason =
				ownership:GetOrCreateTeamRegistration(player, tostring(teamName), definitionId)
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
			RigMechanics.ejectOccupants(existing)
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
		-- A vehicle leaves the facility with a full tank, and carries its own
		-- odometer reading with it.
		--
		-- Fuel is burnt while driving now, which raises the question the previous
		-- comment here flagged: consumption with no way to refuel strands people. The
		-- map has no filling station, and building one blind -- against objects that
		-- do not exist to test against -- would be shipping something unverifiable.
		--
		-- Collecting the vehicle is the refuel instead. You are taking a car out of a
		-- depot or a garage, and it is fuelled when you do, which makes running dry a
		-- reason to go back for it rather than a dead end. The stored figure is still
		-- written throughout the drive, so the record and the MDT show the tank as it
		-- was last seen; it is simply topped up on the next collection.
		--
		-- Mileage is the opposite: it must survive the garage, because that is the
		-- entire point of an odometer.
		local mileage = 0
		if definition.Category == "Civilian" and type(vehicleId) == "string" then
			for _, owned in ownership:List(player) do
				if owned.VehicleId == vehicleId then
					if type(owned.Mileage) == "number" then
						mileage = owned.Mileage
					end
					break
				end
			end
		end
		if self.context.Configuration.VehicleData.FuelEnabled then
			vehicle:SetAttribute("RoleplayOSFuel", 100)
		end
		vehicle:SetAttribute("RoleplayOSMileage", mileage)
		local vehicleSeat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
		if vehicleSeat then
			vehicleSeat:SetAttribute("RoleplayOSRegistration", registration or "")
			vehicleSeat:SetAttribute("RoleplayOSOwnerUserId", player.UserId)
		end
		self:_place(vehicle, bay)
		vehicle.Parent = Workspace
		if vehicleSeat then
			RigMechanics.seatPlayer(player, vehicleSeat)
		end
		-- ELS is deliberately framework-owned, but adoption was never called by the
		-- only service that creates framework vehicles. The server therefore had no
		-- tag/state to expose and every emergency-light controller correctly reported
		-- that the spawned car had no recognised lights.
		if type(definition.DepartmentId) == "string" then
			self.context.Services
				:Get("EmergencyLightsService")
				:Adopt(vehicle, definition.DepartmentId)
			-- A no-op on a vehicle with no EasyLS kit. On one that has it, this is
			-- what actually lights the bar EmergencyLightsService just silenced.
			self.context.Services:Get("EmergencyLightPatternService"):Adopt(vehicle)
		end
		-- Road lighting, which every vehicle has whether or not it is a service one.
		self.context.Services:Get("VehicleLightingService"):Adopt(vehicle)
		self:_removeStockGauges(vehicle)
		self.context.Services:Get("WorldBudgetService"):Normalise(vehicle)
		-- A-Chassis templates are intentionally authored anchored. Their Initialize
		-- script creates the runtime joints and unanchors the correct assemblies.
		-- Reapplying the template's anchored state after that initializer ran froze or
		-- tore down the newly-created chassis and was a primary disappearance cause.
		self:_guardInitialSpawn(vehicle, bay)
		self.active[player.UserId] = vehicle
		self:_beginTelemetry(player, vehicle, vehicleId, mileage)
		self.cooldowns[player.UserId] = os.clock()
		self.spawning[player.UserId] = nil
		vehicle.Destroying:Once(function()
			if self.active[player.UserId] == vehicle then
				self.active[player.UserId] = nil
				-- Last chance to bank the drive before the model goes.
				self:_persistTelemetry(player.UserId, true)
				self.telemetry[player.UserId] = nil
			end
		end)
		return {
			DefinitionId = definitionId,
			ModelName = vehicle.Name,
			Registration = registration,
		},
			nil
	end

	-- Fuel burn and the odometer.
	--
	-- Both readouts on the driver's cluster were decoration before this. Fuel was
	-- written once at spawn and never touched, so the gauge showed one figure for a
	-- whole session; mileage was read by the cluster and stored in the profile but
	-- written by nothing at all, anywhere.
	--
	-- Distance is integrated server-side from the vehicle's own position between
	-- ticks rather than trusted from the client, because fuel is an economic
	-- quantity and mileage ends up on a record the MDT reads.
end
