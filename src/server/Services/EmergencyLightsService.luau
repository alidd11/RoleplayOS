--!strict

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local RolePermissions =
	require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.RolePermissions)
local VehicleLights = require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.VehicleLights)
local EmergencyPatterns =
	require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.EmergencyPatterns)

-- Emergency lighting this framework owns.
--
-- The place runs at least two third party kits, EasyLS and EpicLights, both of
-- them erroring, and neither agreeing with the other about where the state of
-- the lights is kept. That is why the speed cameras had to guess at a dozen
-- attribute names to decide whether a vehicle was on a blue light run, and why
-- guessing wrong quietly costs an emergency driver a fine.
--
-- This service holds the state instead. The cameras then read one attribute
-- that is true because this framework set it, rather than reading a fork.
--
-- The state is all this owns. Every client runs the flash pattern itself from
-- the attribute and a shared clock, so a lightbar strobing twice a second costs
-- nothing on the network however many are running, and a vehicle nobody can see
-- costs nothing at all.
local EmergencyLightsService = { connections = {} }

local function silenceEasyLS(model: Instance): number
	local remote = model:FindFirstChild("EasyLS_Remote", true)
	if not remote then
		return 0
	end
	local silenced = 0
	for _, descendant in remote:GetDescendants() do
		if descendant:IsA("BaseScript") and not descendant.Disabled then
			descendant.Disabled = true
			silenced += 1
		end
	end
	return silenced
end

function EmergencyLightsService:Init(context: any)
	self.context = context
end

function EmergencyLightsService:_settings(): any
	return self.context.Configuration.EmergencyLighting
end

-- Whether a part is one of the vehicle's warning lights.
--
-- Excluded names are checked first and never match, so a headlamp or a brake
-- light is never taken for a blue light. A vehicle whose lights cannot be
-- recognised simply has none, which is visible and fixable, rather than every
-- lamp on the car strobing.
-- The light parts of a vehicle, capped.
--
-- The cap is a guard rather than a target: a lightbar modelled as two hundred
-- separate parts would otherwise be two hundred parts changing colour twice a
-- second on every client that can see it.
function EmergencyLightsService:FindLights(model: Instance): { BasePart }
	local settings = self:_settings()
	local found: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		-- Stop processing once the configured cap is reached. The inner loop's
		-- break prevents additional parts from one group, but without this guard
		-- the outer descendant walk still inspects the rest of the vehicle.
		if settings.MaximumLightParts > 0 and #found >= settings.MaximumLightParts then
			break
		end
		if
			descendant:IsA("BasePart") and VehicleLights.isLightPart(settings, descendant, model)
		then
			table.insert(found, descendant)
			if #found >= settings.MaximumLightParts then
				break
			end
		end
	end
	return found
end

-- Prepares a freshly spawned vehicle.
--
-- Tagging is how clients find it. They watch the tag through CollectionService
-- rather than scanning the world, so a vehicle streaming in is picked up
-- natively and one that never comes near a player is never looked at.
function EmergencyLightsService:Adopt(model: Instance, departmentId: string?)
	local settings = self:_settings()
	if not settings.Enabled then
		return
	end
	local lights = self:FindLights(model)
	if #lights == 0 then
		return
	end
	local department = departmentId and settings.Departments[departmentId]
	if not department then
		-- No colours for this department means no warning lights, rather than
		-- defaulting to blue and putting them on a prison van.
		return
	end
	-- Keep the imported EasyLS hierarchy available for inspection and pattern
	-- migration, but stop its scripts from competing with the framework renderer.
	-- The live clone is the only thing changed; the ServerStorage template remains
	-- untouched and can still be re-exported or inspected by an asset owner.
	local silencedEasyLS = silenceEasyLS(model)
	model:SetAttribute(settings.StateAttribute, false)
	model:SetAttribute(settings.StageAttribute, 0)
	model:SetAttribute(settings.SirenAttribute, "")
	model:SetAttribute(settings.DirectorAttribute, "")
	model:SetAttribute(settings.RunLockAttribute, false)
	model:SetAttribute(settings.LowPowerAttribute, false)
	for circuit in settings.Circuits do
		model:SetAttribute(settings.CircuitAttributePrefix .. circuit, false)
	end
	model:SetAttribute("RoleplayOSLightPrimary", department.Primary)
	model:SetAttribute("RoleplayOSLightSecondary", department.Secondary)
	CollectionService:AddTag(model, settings.Tag)
	if silencedEasyLS > 0 then
		self.context.Logger:Info("EasyLS scripts silenced; RoleplayOS owns emergency lighting", {
			Vehicle = model.Name,
			Scripts = silencedEasyLS,
		})
	end
end

function EmergencyLightsService:_authorised(player: Player): boolean
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil
		and type(duty.DepartmentId) == "string"
		and self:_settings().Departments[duty.DepartmentId] ~= nil
		and RolePermissions.has(self.context.Configuration, duty, "EmergencyLights")
end

-- The vehicle this player is actually driving, or nil.
--
-- Driving it, not owning it and not sitting in it: a passenger reaching for the
-- lights is the same problem as a civilian who found the switch.
function EmergencyLightsService:_drivenVehicle(player: Player): Instance?
	local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then
		return nil
	end
	return seat:FindFirstAncestorOfClass("Model")
end

-- Applies a request, or says why not.
function EmergencyLightsService:Set(player: Player, request: any): (boolean, string?)
	local settings = self:_settings()
	if not settings.Enabled then
		return false, "LIGHTS_DISABLED"
	end
	local model = self:_drivenVehicle(player)
	if not model then
		return false, "NOT_DRIVING"
	end
	if not CollectionService:HasTag(model, settings.Tag) then
		return false, "VEHICLE_HAS_NO_LIGHTS"
	end

	-- On duty with a department that runs lights. Without this, anybody who got
	-- hold of a marked car would have a blue light run available to them, and
	-- with it an exemption from every speed camera in the city.
	local duty = self.context.Services:Get("DutyService"):Get(player)
	if not duty or type(duty.DepartmentId) ~= "string" then
		return false, "NOT_ON_DUTY"
	end
	if not settings.Departments[duty.DepartmentId] then
		return false, "DEPARTMENT_HAS_NO_LIGHTS"
	end
	-- The department decides the colour; the role decides whether they run them
	-- at all. A PCSO is a Police role and does not drive a blue light response,
	-- and the exemption from every speed camera in the city rides on this.
	if not RolePermissions.has(self.context.Configuration, duty, "EmergencyLights") then
		return false, "ROLE_HAS_NO_LIGHTS"
	end

	local stage = model:GetAttribute(settings.StageAttribute)
	if type(stage) ~= "number" then
		stage = 0
	end
	if type(request.Stage) == "number" then
		stage = math.clamp(math.floor(request.Stage), 0, settings.Stages)
	elseif request.Lights ~= nil then
		stage = if request.Lights == true then settings.Stages else 0
	end
	if request.Reset == true then
		stage = 0
		for circuit in settings.Circuits do
			model:SetAttribute(settings.CircuitAttributePrefix .. circuit, false)
		end
		model:SetAttribute(settings.RunLockAttribute, false)
		model:SetAttribute(settings.LowPowerAttribute, false)
		model:SetAttribute(settings.DirectorAttribute, "")
	elseif type(request.Circuit) == "string" then
		if settings.Circuits[request.Circuit] == nil or type(request.Enabled) ~= "boolean" then
			return false, "INVALID_LIGHT_CIRCUIT"
		end
		model:SetAttribute(settings.CircuitAttributePrefix .. request.Circuit, request.Enabled)
	elseif type(request.RunLock) == "boolean" then
		model:SetAttribute(settings.RunLockAttribute, request.RunLock)
	elseif type(request.LowPower) == "boolean" then
		model:SetAttribute(settings.LowPowerAttribute, request.LowPower)
	end

	-- Asking for a tone turns the lights on.
	--
	-- A siren with no lights is not a state anybody wants, and the rule below
	-- clears the tone whenever the stage is zero, so a request for one with the
	-- lights off used to cancel itself. The client tried to compensate with a
	-- second request and could not: the first reply had already overwritten the
	-- state it was testing, so the button did nothing at all, forever.
	if stage == 0 and type(request.Siren) == "string" and request.Siren ~= "" then
		stage = settings.Stages
	end
	model:SetAttribute(settings.StageAttribute, stage)
	local anyCircuit = false
	for circuit in settings.Circuits do
		if model:GetAttribute(settings.CircuitAttributePrefix .. circuit) == true then
			anyCircuit = true
			break
		end
	end
	model:SetAttribute(settings.StateAttribute, stage > 0 or anyCircuit)

	if type(request.Siren) == "string" then
		-- An unknown tone is silence rather than an error. The tones are
		-- configured per deployment and an empty one is the normal state.
		local tone = if settings.Sirens[request.Siren] then request.Siren else ""
		model:SetAttribute(settings.SirenAttribute, tone)
	end
	if stage == 0 then
		model:SetAttribute(settings.SirenAttribute, "")
	end

	-- The arrow-board pattern, independent of the main bar: a vehicle can be at
	-- full response with the director running a lane closure at the same time.
	-- An unrecognised name is silence rather than an error, the same rule the
	-- siren tone follows -- EmergencyPatterns.DirectorStages is the fixed set of
	-- names any kit can use, not a promise this particular vehicle has one, so
	-- EmergencyLightPatternService simply has nothing to paint if it does not.
	if type(request.Director) == "string" then
		local director = if request.Director == ""
				or table.find(EmergencyPatterns.DirectorStages, request.Director)
			then request.Director
			else ""
		model:SetAttribute(settings.DirectorAttribute, director)
	end

	return true, nil
end

-- What the interface should show. Read only, so it is safe for any caller.
function EmergencyLightsService:GetState(player: Player): any
	local settings = self:_settings()
	local model = self:_drivenVehicle(player)
	-- Which gate closed, not just that one did.
	--
	-- All three of these produced the same silent Available = false, so a panel
	-- that did not appear gave no way to tell whether the player was in a vehicle
	-- this framework never spawned, in one whose lights could not be recognised,
	-- or simply not allowed to use them. Three very different problems with one
	-- symptom and nothing to separate them.
	local reason: string? = nil
	if not model then
		reason = "NOT_DRIVING_A_FRAMEWORK_VEHICLE"
	elseif not CollectionService:HasTag(model, settings.Tag) then
		reason = "VEHICLE_HAS_NO_RECOGNISED_LIGHTS"
	elseif not self:_authorised(player) then
		reason = "ROLE_MAY_NOT_USE_LIGHTS"
	end
	if reason then
		return { Available = false, Reason = reason, Stage = 0, Lights = false, Siren = "" }
	end
	local circuits = {}
	for circuit in settings.Circuits do
		circuits[circuit] = model:GetAttribute(settings.CircuitAttributePrefix .. circuit) == true
	end
	-- Which circuits this vehicle owns a lamp for.
	--
	-- Front and rear blues resolve from where a lamp sits and what colour its
	-- lens is, so they work on any model. The specialised circuits cannot be
	-- guessed that way and are only found by an explicit attribute or a
	-- recognisable part name, which the imported kits do not use: their bulbs
	-- are called things like F1 and R2. Offering all nine regardless meant seven
	-- buttons that recorded a state against no lamp at all - the click worked,
	-- the server agreed, and nothing lit. The panel now shows what the vehicle
	-- in front of the player can actually do.
	local available = {}
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart") and VehicleLights.isLightPart(settings, descendant, model)
		then
			local circuit = VehicleLights.circuitFor(settings, descendant, model)
			if circuit then
				available[circuit] = true
			end
		end
	end
	-- The director patterns this specific vehicle actually has -- an arrow
	-- board is not something every EasyLS vehicle carries, and EmergencyPatterns
	-- reads the kit itself rather than guessing from a fixed count. Empty for a
	-- vehicle with no kit at all, which is most of the fleet.
	local directorStages = {}
	local kit = EmergencyPatterns.read(model)
	if kit then
		for _, name in EmergencyPatterns.DirectorStages do
			if kit.Stages[name] then
				table.insert(directorStages, name)
			end
		end
	end
	return {
		Available = true,
		AvailableCircuits = available,
		Stage = model:GetAttribute(settings.StageAttribute) or 0,
		Lights = model:GetAttribute(settings.StateAttribute) == true,
		Siren = model:GetAttribute(settings.SirenAttribute) or "",
		Director = model:GetAttribute(settings.DirectorAttribute) or "",
		DirectorStages = directorStages,
		-- What this vehicle can actually sound.
		--
		-- This was settings.Sirens, a table of ids nothing plays: the client
		-- sounds the vehicle's own Sound instances by name. Two of the four ids
		-- are empty strings, and the panel skips a tone whose entry is empty, so
		-- Phaser and Horn were absent from the cycle on every vehicle - including
		-- the bikes, which carry Priority and Airhorn and can sound both.
		Tones = VehicleLights.availableTones(model),
		Circuits = circuits,
		RunLock = model:GetAttribute(settings.RunLockAttribute) == true,
		LowPower = model:GetAttribute(settings.LowPowerAttribute) == true,
	}
end

-- Adopts the vehicles that were parked in the world rather than spawned.
--
-- Adopt was called from exactly one place: the spawner, at the moment it
-- creates a vehicle. A car placed in the map by hand therefore never went
-- through it, was never tagged, and every client asking about its lights got
-- VEHICLE_HAS_NO_RECOGNISED_LIGHTS -- so the lighting panel never appeared, for
-- a vehicle that may well have had a full lightbar on it.
--
-- The department is what decides the colours, and a parked model carries no
-- spawn definition to read it from. Two ways to say it, in order: an attribute
-- on the model itself, which needs no code and no catalogue entry, or a
-- catalogue entry matched on the model's name.
--
-- Anything that resolves to neither is listed by name in the log rather than
-- passed over in silence, because "which of the things in my map did this not
-- recognise" is the question somebody is going to have, and the answer is
-- cheap to give.
function EmergencyLightsService:Start()
	local settings = self:_settings()
	if not settings.Enabled then
		return
	end
	task.spawn(function()
		local byModelName: { [string]: any } = {}
		local validator = self.context.Services:Get("ContentValidationService")
		local vehicleDefinitions = if validator and validator.GetVehicleDefinitions
			then validator:GetVehicleDefinitions()
			else self.context.Configuration.Vehicles
		for _, definition in vehicleDefinitions do
			local name = definition.WorkspaceModelName or definition.ModelName or definition.Id
			if type(name) == "string" then
				byModelName[name] = definition
			end
		end
		local adopted, unknown, unlit = 0, {}, {}
		for _, child in Workspace:GetChildren() do
			if not child:IsA("Model") or not child:FindFirstChildWhichIsA("VehicleSeat", true) then
				continue
			end
			if CollectionService:HasTag(child, settings.Tag) then
				continue
			end
			local attribute = child:GetAttribute("RoleplayOSDepartmentId")
				or child:GetAttribute("DepartmentId")
			local definition = byModelName[child.Name]
			local departmentId = if type(attribute) == "string"
				then attribute
				else (definition and definition.DepartmentId)
			-- A department nobody has given colours to is the same outcome as no
			-- department at all, and the same remedy, so they are reported
			-- together rather than as a mystery about the model's lamps.
			if type(departmentId) ~= "string" or not settings.Departments[departmentId] then
				table.insert(unknown, child.Name)
				continue
			end
			self:Adopt(child, departmentId)
			self.context.Services:Get("EmergencyLightPatternService"):Adopt(child)
			if CollectionService:HasTag(child, settings.Tag) then
				adopted += 1
			else
				-- A department was found and the lights still were not. Separated
				-- from the case above because the remedy is completely different:
				-- this one is about what the model is built from, not about what
				-- the framework was told.
				table.insert(unlit, child.Name)
			end
		end
		self.context.Logger:Info("Parked emergency vehicles adopted", { Adopted = adopted })
		if #unknown > 0 then
			self.context.Logger:Warning("Parked vehicles with no department to light them", {
				Models = unknown,
				Remedy = "Set a RoleplayOSDepartmentId attribute naming a department that has "
					.. "colours configured, or add the model to Vehicles",
			})
		end
		if #unlit > 0 then
			self.context.Logger:Warning("Parked vehicles whose lights were not recognised", {
				Models = unlit,
				Remedy = "Lamps need a Light child, Neon material or a saturated colour",
			})
		end
	end)
end

function EmergencyLightsService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return EmergencyLightsService
