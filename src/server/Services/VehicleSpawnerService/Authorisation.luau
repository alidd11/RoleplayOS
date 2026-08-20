--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RigMechanics = require(script.Parent.RigMechanics)

local PREVIEW_IDLE_SECONDS = 60 * 60

return function(VehicleSpawnerService)
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

	function VehicleSpawnerService:_authorise(
		player: Player,
		spawnerId: string
	): (Instance?, string?)
		local spawner = self:_spawner(spawnerId)
		if not spawner then
			return nil, "SPAWNER_NOT_FOUND"
		end
		local playerPosition = RigMechanics.rootPosition(player)
		local position = RigMechanics.modelPosition(spawner)
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
			if
				type(divisionId) == "string"
				and divisionId ~= ""
				and duty.DivisionId ~= divisionId
			then
				return nil, "WRONG_DIVISION"
			end
			return spawner, nil
		end
		-- A gang's own facility at its territory: the same shape, a different
		-- authority. The check is against who currently holds the territory, not
		-- against a name on the spawner itself, so a facility follows a contested
		-- zone through a flip without anything here needing to change.
		local territoryId = spawner:GetAttribute("TerritoryId")
		if type(territoryId) == "string" and territoryId ~= "" then
			local ownerGangId =
				self.context.Services:Get("GangTerritoryService"):OwnerOf(territoryId)
			local session = self.context.Services:Get("DataService"):GetSession(player)
			local gangId = session and session.Profile.GangId
			if not ownerGangId or type(gangId) ~= "string" or gangId ~= ownerGangId then
				return nil, "GANG_TERRITORY_NOT_HELD"
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
			-- Which unit's fleet this terminal is showing.
			--
			-- A terminal may name a division, in which case it is that unit's bay and
			-- only that unit's vehicles belong on it. Where it names none it serves
			-- the whole department from one place, and then the division that matters
			-- is the one the officer came on duty as - otherwise a single shared
			-- terminal hands every officer the keys to every unit's fleet.
			--
			-- Vehicles with no division of their own are the department's general
			-- stock and stay available either way.
			local divisionId = spawner:GetAttribute("DivisionId")
			if type(divisionId) ~= "string" or divisionId == "" then
				local duty = self.context.Services:Get("DutyService"):Get(player)
				divisionId = duty and duty.DivisionId
			end
			return type(divisionId) ~= "string"
				or divisionId == ""
				or definition.DivisionId == nil
				or definition.DivisionId == divisionId
		end
		-- Named explicitly rather than left to fall into the generic non-Civilian
		-- branch below: that branch authorises any Fleet vehicle regardless of
		-- category, which is looser than a gang facility should be.
		if definition.Category == "Gang" then
			return definition.Fleet == true
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

	-- A showroom copy of a vehicle, for the forecourt's 3D preview.
	--
	-- The templates live in ServerStorage and never reach a client, so a viewport
	-- there has nothing to render. This publishes a stripped copy: geometry and
	-- nothing else, with every script, sound, light, joint and value removed, so
	-- what replicates is the shape of the car rather than a second working vehicle.
	--
	-- Built when somebody first opens a forecourt rather than at startup, so a
	-- server whose players never visit a dealership never pays to replicate them.

	function VehicleSpawnerService:_ensurePreview(definitionId: string, definition: any): Instance?
		local root = ReplicatedStorage:FindFirstChild("RoleplayOSVehiclePreviews")
		if not root then
			root = Instance.new("Folder")
			root.Name = "RoleplayOSVehiclePreviews"
			root.Parent = ReplicatedStorage
		end
		local existing = root:FindFirstChild(definitionId)
		if existing then
			self.previewLastUsed[definitionId] = os.clock()
			return existing
		end
		local template = self:_template(definition)
		if not template then
			return nil
		end
		local preview = template:Clone()
		preview.Name = definitionId
		for _, descendant in preview:GetDescendants() do
			if
				descendant:IsA("BaseScript")
				or descendant:IsA("ModuleScript")
				or descendant:IsA("Sound")
				or descendant:IsA("Light")
				or descendant:IsA("ParticleEmitter")
				or descendant:IsA("Constraint")
				or descendant:IsA("JointInstance")
				or descendant:IsA("ValueBase")
				or descendant:IsA("ProximityPrompt")
				or descendant:IsA("LayerCollector")
				or descendant:IsA("Configuration")
			then
				descendant:Destroy()
			end
		end
		for _, descendant in preview:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end
		preview.Parent = root
		self.previewLastUsed[definitionId] = os.clock()
		return preview
	end

	-- Showroom previews contain only anchored geometry, but a long-running full
	-- server can still accumulate one copy for every vehicle ever browsed. They
	-- are rebuilt on demand, so expiring an idle entry releases memory without
	-- affecting ownership, spawned vehicles or persistent data.
	function VehicleSpawnerService:_prunePreviews()
		local root = ReplicatedStorage:FindFirstChild("RoleplayOSVehiclePreviews")
		if not root then
			return
		end
		local now = os.clock()
		for definitionId, lastUsed in self.previewLastUsed do
			if now - lastUsed >= PREVIEW_IDLE_SECONDS then
				local preview = root:FindFirstChild(definitionId)
				if preview then
					preview:Destroy()
				end
				self.previewLastUsed[definitionId] = nil
			end
		end
		if #root:GetChildren() == 0 then
			root:Destroy()
		end
	end

	function VehicleSpawnerService:Menu(player: Player, spawnerId: string): (any?, string?)
		local spawner, reason = self:_authorise(player, spawnerId)
		if not spawner then
			return nil, reason
		end
		local vehicles = {}
		local departmentId = spawner:GetAttribute("DepartmentId")
		local territoryId = spawner:GetAttribute("TerritoryId")
		local isIssuedFacility = (type(departmentId) == "string" and departmentId ~= "")
			or (type(territoryId) == "string" and territoryId ~= "")
		if isIssuedFacility then
			for id, definition in self:_vehicleDefinitions() do
				local template = self:_template(definition)
				if self:_definitionAllowed(player, spawner, definition) and template then
					self:_ensurePreview(id, definition)
					table.insert(vehicles, {
						Id = id,
						Name = definition.Name,
						Category = definition.Category,
						DivisionId = definition.DivisionId,
						-- Issued, never sold. A department vehicle belongs to the unit
						-- rather than to the officer, so this terminal takes one out and
						-- has nothing to charge for. Saying so here is what stops the
						-- forecourt's buy flow from being offered at a police bay,
						-- where it read as a free car nobody could actually take.
						Spawnable = true,
					})
				end
			end
		else
			-- A forecourt, not a garage list.
			--
			-- This offered only what the player already owned, so the dealership's
			-- catalogue and every price in it were unreachable: there was no screen
			-- anywhere that showed a car for sale. Everything the forecourt sells is
			-- listed now, each entry saying whether this character owns one, and the
			-- owned copies are listed after it so a second Civic is a separate row
			-- with its own registration rather than a duplicate of the catalogue.
			local ownership = self.context.Services:Get("VehicleOwnershipService")
			local owned = ownership:List(player)
			local ownedByDefinition: { [string]: boolean } = {}
			for _, vehicle in owned do
				ownedByDefinition[vehicle.DefinitionId] = true
			end
			-- The forecourt this spawner sells from. Defaults to the only one
			-- configured rather than to the spawner's own name, which is
			-- CityDealership in the map and CityMotors in configuration.
			local dealershipId = spawner:GetAttribute("DealershipId") or "CityMotors"
			local dealership = self.context.Configuration.Dealerships[dealershipId]
			local forecourt = dealership and dealership.VehicleIds
			-- Where a spawner names no dealership, everything civilian is for sale
			-- rather than nothing, so a new forecourt is useful before it is
			-- configured rather than empty until somebody notices.
			if not forecourt then
				forecourt = {}
				for id, definition in self:_vehicleDefinitions() do
					if definition.Category == "Civilian" and definition.Fleet ~= true then
						table.insert(forecourt, id)
					end
				end
			end
			for _, definitionId in forecourt do
				local definition = self:_vehicleDefinition(definitionId)
				local template = definition and self:_template(definition)
				if definition and definition.Category == "Civilian" and template then
					local access = self.context.Services
						:Get("AccessService")
						:Evaluate(player, definition.Access)
					self:_ensurePreview(definitionId, definition)
					table.insert(vehicles, {
						Id = definitionId,
						Name = definition.Name,
						Category = "Civilian",
						Price = definition.Price,
						Colours = definition.Colours,
						Owned = ownedByDefinition[definitionId] == true,
						Locked = not access.Allowed,
						LockReason = if access.Allowed then nil else access.ReasonCode,
						ForSale = true,
					})
				end
			end
			for _, vehicle in owned do
				local definition = self:_vehicleDefinition(vehicle.DefinitionId)
				local template = definition and self:_template(definition)
				if definition and definition.Category == "Civilian" and template then
					table.insert(vehicles, {
						Id = vehicle.DefinitionId,
						VehicleId = vehicle.VehicleId,
						Name = definition.Name,
						Category = "Civilian",
						Registration = vehicle.Registration,
						Colour = vehicle.Colour,
						Fuel = vehicle.Fuel,
						Condition = vehicle.Condition,
						Mileage = vehicle.Mileage,
						Insured = vehicle.Insured,
						Taxed = vehicle.Taxed,
						Owned = true,
					})
				end
			end
		end
		table.sort(vehicles, function(a, b)
			-- What is for sale first, cheapest first, then the cars this character
			-- already keeps here. Sorting the two together interleaved a showroom
			-- entry with its own owned copies.
			if (a.ForSale == true) ~= (b.ForSale == true) then
				return a.ForSale == true
			end
			if a.ForSale == true and a.Price ~= b.Price then
				return (a.Price or 0) < (b.Price or 0)
			end
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
end
