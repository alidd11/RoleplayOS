--!strict

local CollectionService = game:GetService("CollectionService")

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

local function matchesAny(name: string, patterns: { string }): boolean
	local lowered = string.lower(name)
	for _, pattern in patterns do
		if string.find(lowered, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Whether a part is one of the vehicle's warning lights.
--
-- Excluded names are checked first and never match, so a headlamp or a brake
-- light is never taken for a blue light. A vehicle whose lights cannot be
-- recognised simply has none, which is visible and fixable, rather than every
-- lamp on the car strobing.
function EmergencyLightsService:_isLightPart(part: BasePart): boolean
	local settings = self:_settings()
	if matchesAny(part.Name, settings.ExcludedNamePatterns) then
		return false
	end
	return matchesAny(part.Name, settings.LightNamePatterns)
end

-- The light parts of a vehicle, capped.
--
-- The cap is a guard rather than a target: a lightbar modelled as two hundred
-- separate parts would otherwise be two hundred parts changing colour twice a
-- second on every client that can see it.
function EmergencyLightsService:FindLights(model: Instance): { BasePart }
	local settings = self:_settings()
	local found: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and self:_isLightPart(descendant) then
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
	model:SetAttribute("RoleplayOSLightPrimary", department.Primary)
	model:SetAttribute("RoleplayOSLightSecondary", department.Secondary)
	CollectionService:AddTag(model, settings.Tag)
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

	local stage = model:GetAttribute(settings.StageAttribute)
	if type(stage) ~= "number" then
		stage = 0
	end
	if type(request.Stage) == "number" then
		stage = math.clamp(math.floor(request.Stage), 0, settings.Stages)
	elseif request.Lights ~= nil then
		stage = if request.Lights == true then settings.Stages else 0
	end

	model:SetAttribute(settings.StageAttribute, stage)
	model:SetAttribute(settings.StateAttribute, stage > 0)

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
	if not model or not CollectionService:HasTag(model, settings.Tag) then
		return { Available = false, Stage = 0, Lights = false, Siren = "" }
	end
	return {
		Available = true,
		Stage = model:GetAttribute(settings.StageAttribute) or 0,
		Lights = model:GetAttribute(settings.StateAttribute) == true,
		Siren = model:GetAttribute(settings.SirenAttribute) or "",
		Tones = settings.Sirens,
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
