--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local RoadSafetyService = {
	connections = {},
	sensorConnections = {},
	cooldowns = {},
	journeys = {},
}

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
): boolean
	local player, character = self:_owner(vehicle)
	if not player or not character then
		return false
	end
	local excess = math.floor(mph - limit + 0.5)
	if excess <= self.context.Configuration.RoadSafety.ToleranceMph then
		return false
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
	return true
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
	local telemetry = self.context.Services:Get("VehicleService"):GetTelemetry(vehicle)
	if not telemetry then
		return
	end
	local issued = self:_issue(
		vehicle,
		sensor,
		telemetry.SpeedMph,
		sensor:GetAttribute("SpeedLimitMph") or 30,
		"Fixed"
	)
	self.cooldowns[key] = now
		+ (if issued then self.context.Configuration.RoadSafety.SensorCooldownSeconds else 1)
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
	local function watch(sensor: Instance)
		if not sensor:IsA("BasePart") or self.sensorConnections[sensor] then
			return
		end
		self.sensorConnections[sensor] = sensor.Touched:Connect(function(hit)
			callback(sensor, hit)
		end)
	end
	local function unwatch(sensor: Instance)
		local connection = self.sensorConnections[sensor]
		if connection then
			connection:Disconnect()
			self.sensorConnections[sensor] = nil
		end
	end
	for _, sensor in CollectionService:GetTagged(tag) do
		watch(sensor)
	end
	table.insert(self.connections, CollectionService:GetInstanceAddedSignal(tag):Connect(watch))
	table.insert(self.connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatch))
end

function RoadSafetyService:_cleanup(now: number)
	for key, expiresAt in self.cooldowns do
		if expiresAt <= now then
			self.cooldowns[key] = nil
		end
	end
	local maximumJourneyAge = self.context.Configuration.RoadSafety.AverageJourneyExpirySeconds
	for key, journey in self.journeys do
		if now - journey.Time > maximumJourneyAge then
			self.journeys[key] = nil
		end
	end
end

function RoadSafetyService:Start()
	self.running = true
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
	task.spawn(function()
		while self.running do
			task.wait(config.StateCleanupSeconds)
			self:_cleanup(os.clock())
		end
	end)
end

function RoadSafetyService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.sensorConnections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.sensorConnections)
	table.clear(self.journeys)
	table.clear(self.cooldowns)
end

return RoadSafetyService
