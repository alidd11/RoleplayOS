--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local RoadSafetyService = { connections = {}, cooldowns = {}, journeys = {} }

function RoadSafetyService:Init(context: any)
	self.context = context
end

function RoadSafetyService:_vehicleFromPart(part: BasePart): Model?
	local current: Instance? = part
	while current and current ~= workspace do
		if
			current:IsA("Model")
			and type(current:GetAttribute("RoleplayOSRegistration")) == "string"
		then
			return current
		end
		current = current.Parent
	end
	return nil
end

function RoadSafetyService:_owner(vehicle: Model): (Player?, any?)
	local userId = vehicle:GetAttribute("RoleplayOSOwnerUserId")
	local characterId = vehicle:GetAttribute("RoleplayOSOwnerCharacterId")
	if type(userId) ~= "number" or type(characterId) ~= "string" then
		return nil, nil
	end
	local player = Players:GetPlayerByUserId(userId)
	local session = player and self.context.Services:Get("DataService"):GetSession(player)
	return player, session and session.Profile.Characters[characterId]
end

function RoadSafetyService:_points(excess: number): number
	for _, band in self.context.Configuration.RoadSafety.PointsByExcess do
		if excess <= band[1] then
			return band[2]
		end
	end
	return 6
end

function RoadSafetyService:_issue(
	vehicle: Model,
	camera: BasePart,
	mph: number,
	limit: number,
	kind: string
)
	local player, character = self:_owner(vehicle)
	if not player or not character then
		return
	end
	local excess = math.floor(mph - limit + 0.5)
	if excess <= self.context.Configuration.RoadSafety.ToleranceMph then
		return
	end
	character.DrivingRecord = character.DrivingRecord or { Points = 0, Fines = {} }
	local points = self:_points(excess)
	local fine = math.min(
		self.context.Configuration.RoadSafety.MaximumFine,
		self.context.Configuration.RoadSafety.FineBase
			+ excess * self.context.Configuration.RoadSafety.FinePerMph
	)
	local record = {
		FineId = HttpService:GenerateGUID(false),
		IssuedAt = os.time(),
		Registration = vehicle:GetAttribute("RoleplayOSRegistration"),
		Location = camera:GetAttribute("Location") or camera.Name,
		CameraId = camera:GetAttribute("CameraId") or camera.Name,
		Type = kind,
		RecordedMph = math.floor(mph + 0.5),
		LimitMph = limit,
		Fine = fine,
		Points = points,
		Status = "Unpaid",
	}
	table.insert(character.DrivingRecord.Fines, record)
	character.DrivingRecord.Points = math.min(99, (character.DrivingRecord.Points or 0) + points)
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = 0,
		Action = "RoadSafety.OffenceIssued",
		Target = character.CharacterId,
		Metadata = record,
	})
end

function RoadSafetyService:_fixed(sensor: BasePart, hit: BasePart)
	local vehicle = self:_vehicleFromPart(hit)
	if not vehicle then
		return
	end
	local registration = vehicle:GetAttribute("RoleplayOSRegistration")
	local key = sensor:GetFullName() .. ":" .. tostring(registration)
	local now = os.clock()
	if (self.cooldowns[key] or 0) > now then
		return
	end
	self.cooldowns[key] = now + self.context.Configuration.RoadSafety.SensorCooldownSeconds
	local primary = vehicle.PrimaryPart or hit
	local mph = primary.AssemblyLinearVelocity.Magnitude
		* self.context.Configuration.RoadSafety.StudsPerSecondToMph
	self:_issue(vehicle, sensor, mph, sensor:GetAttribute("SpeedLimitMph") or 30, "Fixed")
end

function RoadSafetyService:_average(sensor: BasePart, hit: BasePart, isEntry: boolean)
	local vehicle = self:_vehicleFromPart(hit)
	if not vehicle then
		return
	end
	local registration = vehicle:GetAttribute("RoleplayOSRegistration")
	local corridor = sensor:GetAttribute("CorridorId") or "Default"
	local key = tostring(registration) .. ":" .. corridor
	if isEntry then
		self.journeys[key] = { Time = os.clock(), Position = sensor.Position }
		return
	end
	local entry = self.journeys[key]
	self.journeys[key] = nil
	if not entry then
		return
	end
	local elapsed = os.clock() - entry.Time
	if
		elapsed <= 0
		or elapsed > self.context.Configuration.RoadSafety.AverageJourneyExpirySeconds
	then
		return
	end
	local mph = (sensor.Position - entry.Position).Magnitude
		/ elapsed
		* self.context.Configuration.RoadSafety.StudsPerSecondToMph
	self:_issue(vehicle, sensor, mph, sensor:GetAttribute("SpeedLimitMph") or 30, "Average")
end

function RoadSafetyService:_connect(tag: string, callback: (BasePart, BasePart) -> ())
	for _, sensor in CollectionService:GetTagged(tag) do
		if sensor:IsA("BasePart") then
			table.insert(
				self.connections,
				sensor.Touched:Connect(function(hit)
					callback(sensor, hit)
				end)
			)
		end
	end
end

function RoadSafetyService:Start()
	local config = self.context.Configuration.RoadSafety
	self:_connect(config.SpeedCameraTag, function(sensor, hit)
		self:_fixed(sensor, hit)
	end)
	self:_connect(config.AverageEntryTag, function(sensor, hit)
		self:_average(sensor, hit, true)
	end)
	self:_connect(config.AverageExitTag, function(sensor, hit)
		self:_average(sensor, hit, false)
	end)
end

function RoadSafetyService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.journeys)
	table.clear(self.cooldowns)
end

return RoadSafetyService
