--!strict

local CollectionService = game:GetService("CollectionService")
local RolePermissions =
	require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.RolePermissions)
local VehicleLights = require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.VehicleLights)

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
	model:SetAttribute(settings.StateAttribute, false)
	model:SetAttribute(settings.StageAttribute, 0)
	model:SetAttribute(settings.SirenAttribute, "")
	model:SetAttribute(settings.RunLockAttribute, false)
	model:SetAttribute(settings.LowPowerAttribute, false)
	for circuit in settings.Circuits do
		model:SetAttribute(settings.CircuitAttributePrefix .. circuit, false)
	end
	model:SetAttribute("RoleplayOSLightPrimary", department.Primary)
	model:SetAttribute("RoleplayOSLightSecondary", department.Secondary)
	CollectionService:AddTag(model, settings.Tag)
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
	local active = self.context.Services:Get("VehicleService").activeByUserId[player.UserId]
	if not active or not active.Model or not active.Model.Parent then
		return nil
	end
	local seat = active.Seat
	if not seat or seat.Occupant == nil then
		return nil
	end
	-- The occupant is a Humanoid; its parent is the character sitting there.
	local character = seat.Occupant.Parent
	return if character ~= nil and character == player.Character then active.Model else nil
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
	return {
		Available = true,
		Stage = model:GetAttribute(settings.StageAttribute) or 0,
		Lights = model:GetAttribute(settings.StateAttribute) == true,
		Siren = model:GetAttribute(settings.SirenAttribute) or "",
		Tones = settings.Sirens,
		Circuits = circuits,
		RunLock = model:GetAttribute(settings.RunLockAttribute) == true,
		LowPower = model:GetAttribute(settings.LowPowerAttribute) == true,
	}
end

function EmergencyLightsService:Start() end

function EmergencyLightsService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return EmergencyLightsService
