--!strict

-- Speeding: who is exempt, what it costs, and where it is recorded.
--
-- Detection is not here. The speed camera system placed in the world measures
-- the speed and calls IssueFine; this decides whether the driver should have
-- been fined at all, works out the penalty, and writes it to the character's
-- driving record so the MDT shows it and RecordIndexService publishes it into
-- the person record. A camera keeping its own tally somewhere else is invisible
-- to every one of those.
--
-- The exemption is the interesting part. An emergency driver on a blue light run
-- is not speeding, they are responding; the same driver with the lights off is
-- just speeding in a marked car. So the exemption belongs to the response rather
-- than to the person or the vehicle, and it is checked at the moment the camera
-- reports, because that is the only moment it is true of.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

-- The name a camera system looks for. A BindableFunction rather than a module,
-- so a script that knows nothing about RoleplayOS and cannot require anything
-- from it can still ask.
local BRIDGE_NAME = "RoleplayOSIssueFine"

local RoadSafetyService = {}

function RoadSafetyService:Init(context: any)
	self.context = context
end

-- A door for the camera system in the world.
--
-- It lives in ServerStorage under a fixed name, so a camera script parented
-- anywhere on the server can find it without requiring anything, and it takes
-- the same table IssueFine does. Anything that goes wrong inside is reported to
-- the caller rather than raised, since a camera should not stop working because
-- one reading was malformed.
function RoadSafetyService:Start()
	local bridge = Instance.new("BindableFunction")
	bridge.Name = BRIDGE_NAME
	bridge.OnInvoke = function(request: any)
		local ok, issued, reason = pcall(function()
			return self:IssueFine(request)
		end)
		if not ok then
			self.context.Logger:Error("Speed camera fine raised", { Error = tostring(issued) })
			return false, "ISSUE_FAILED"
		end
		return issued, reason
	end
	bridge.Parent = ServerStorage
	self.bridge = bridge
end

-- Whether a value read from an attribute or a value object means "lights on".
--
-- Lighting systems express this differently: a boolean, a number of the active
-- stage, or the name of a mode. Anything present and not explicitly off counts,
-- because a missing signal is far more likely than a system that reports being
-- on by saying nothing.
function RoadSafetyService:_readsAsOn(value: any): boolean
	if value == nil then
		return false
	end
	if type(value) == "boolean" then
		return value
	end
	if type(value) == "number" then
		return value > 0
	end
	if type(value) ~= "string" then
		return false
	end
	local lowered = string.lower(value)
	for _, off in self.context.Configuration.EmergencyLights.OffValues do
		if lowered == off then
			return false
		end
	end
	return lowered ~= ""
end

-- Whether this vehicle's blue lights are on.
--
-- Every configured name is tried as an attribute on the model and on the seat,
-- then as a value object inside each configured folder. Nothing here assumes a
-- particular lighting system, because there is no reason to expect one.
function RoadSafetyService:AreLightsOn(vehicle: Instance?): boolean
	if not vehicle then
		return false
	end
	local settings = self.context.Configuration.EmergencyLights
	local roots: { Instance } = { vehicle }
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat then
		table.insert(roots, seat)
	end

	for _, root in roots do
		for _, name in settings.AttributeNames do
			if self:_readsAsOn(root:GetAttribute(name)) then
				return true
			end
		end
	end

	for _, folderName in settings.ValueFolderNames do
		local folder = vehicle:FindFirstChild(folderName, true)
		if folder then
			for _, name in settings.AttributeNames do
				if self:_readsAsOn(folder:GetAttribute(name)) then
					return true
				end
				local item = folder:FindFirstChild(name)
				if item and item:IsA("ValueBase") and self:_readsAsOn((item :: any).Value) then
					return true
				end
			end
		end
	end
	return false
end

-- Whether this driver, in this vehicle, right now, should be let off.
function RoadSafetyService:IsExempt(player: Player, vehicle: Instance?): boolean
	local settings = self.context.Configuration.RoadSafety
	if settings.ExemptOnEmergencyLights ~= true then
		return false
	end
	if not self:AreLightsOn(vehicle) then
		return false
	end
	if settings.ExemptRequiresDuty ~= true then
		return true
	end
	-- On duty with an emergency service. Without this, anybody who got hold of a
	-- marked car and found the light switch would be exempt.
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil and type(duty.DepartmentId) == "string"
end

-- Penalty points for how far over the limit somebody was, from the configured
-- bands. They are ordered, so the first band the excess falls inside wins.
function RoadSafetyService:_points(excess: number): number
	for _, band in self.context.Configuration.RoadSafety.PointsByExcess do
		if excess <= band[1] then
			return band[2]
		end
	end
	return 0
end

-- The character to fine, found from the registration rather than from whoever
-- is sitting in the car. The registered keeper is responsible for their
-- vehicle, which is both how it works and the only thing a camera can know.
function RoadSafetyService:_keeper(registration: string): (Player?, any?)
	local vehicle, player =
		self.context.Services:Get("VehicleOwnershipService"):GetByRegistration(registration)
	if not vehicle or not player then
		return nil, nil
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local characterId = session and session.ActiveCharacterId
	local character = characterId and session.Profile.Characters[characterId]
	if not character or character.CharacterId ~= vehicle.OwnerCharacterId then
		-- The keeper is playing somebody else at the moment. The fine belongs to
		-- the character that owns the car, not to whoever they happen to be.
		return nil, nil
	end
	return player, character
end

-- Records a speeding offence, unless the driver was exempt.
--
-- This is the whole public surface a camera needs. It is given what was
-- measured and, where the camera knows it, the vehicle and the driver, so the
-- exemption can be judged. Returns false with a reason rather than raising: an
-- exempt run and an unregistered car are both ordinary outcomes, not errors
-- worth interrupting a camera for.
function RoadSafetyService:IssueFine(request: any): (boolean, string?)
	if type(request) ~= "table" then
		return false, "INVALID_REQUEST"
	end
	local registration = request.Registration
	if type(registration) ~= "string" or registration == "" then
		return false, "INVALID_REGISTRATION"
	end
	local speed = tonumber(request.Mph)
	local allowed = tonumber(request.LimitMph)
	if not speed or not allowed or allowed <= 0 then
		return false, "INVALID_SPEED"
	end

	local settings = self.context.Configuration.RoadSafety
	local excess = math.floor(speed - allowed + 0.5)
	if excess <= settings.ToleranceMph then
		return false, "WITHIN_TOLERANCE"
	end

	local player, character = self:_keeper(registration)
	if not player or not character then
		return false, "KEEPER_UNAVAILABLE"
	end

	-- Judged against whoever is driving, which is not necessarily the keeper: an
	-- officer on a response in a car registered to somebody else is still on a
	-- response, and the keeper should not be fined for it.
	local driver = request.Driver
	if typeof(driver) ~= "Instance" or not driver:IsA("Player") then
		driver = player
	end
	if self:IsExempt(driver, request.Vehicle) then
		return false, "EXEMPT_EMERGENCY_RESPONSE"
	end

	local points = self:_points(excess)
	local fine = math.min(settings.MaximumFine, settings.FineBase + excess * settings.FinePerMph)
	local record = {
		FineId = HttpService:GenerateGUID(false),
		IssuedAt = os.time(),
		Registration = registration,
		Location = if type(request.Location) == "string" then request.Location else "Speed camera",
		Type = if type(request.Kind) == "string" then request.Kind else "SpeedCamera",
		RecordedMph = math.floor(speed + 0.5),
		LimitMph = math.floor(allowed + 0.5),
		Fine = fine,
		Points = points,
		Status = "Unpaid",
	}

	character.DrivingRecord = character.DrivingRecord or { Points = 0, Fines = {} }
	character.DrivingRecord.Fines = character.DrivingRecord.Fines or {}
	table.insert(character.DrivingRecord.Fines, record)
	-- Trimmed oldest first. Cameras issue these unattended, so this is the one
	-- history in a profile that grows without anybody choosing to add to it, and
	-- a profile that outgrows the store stops saving entirely.
	local maximum = self.context.Configuration.Framework.MaximumDrivingFines or 80
	while #character.DrivingRecord.Fines > maximum do
		table.remove(character.DrivingRecord.Fines, 1)
	end
	character.DrivingRecord.Points = math.min(99, (character.DrivingRecord.Points or 0) + points)

	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services:Get("RecordIndexService"):ScheduleCharacter(player, character)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = 0,
		Action = "RoadSafety.OffenceIssued",
		Target = character.CharacterId,
		Metadata = record,
	})
	return true, nil
end

function RoadSafetyService:Destroy()
	if self.bridge then
		self.bridge:Destroy()
		self.bridge = nil
	end
end

return RoadSafetyService
