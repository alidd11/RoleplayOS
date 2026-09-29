--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapProjection = require(ReplicatedStorage.RoleplayOS.Shared.MapProjection)
local ANPRService = { connections = {}, cooldowns = {}, watched = {}, watchedCount = 0 }

function ANPRService:Init(context: any)
	self.context = context
	self.alertEvent = context.Network:RegisterEvent("ANPRAlert")
end

function ANPRService:_alertPlayers(): { Player }
	local result = {}
	for _, player in Players:GetPlayers() do
		local duty = self.context.Services:Get("DutyService"):Get(player)
		if
			duty
			and (
				duty.RoleId == self.context.Configuration.ANPR.RoadsRoleId
				or duty.DepartmentId == "Control"
			)
		then
			table.insert(result, player)
		end
	end
	return result
end

function ANPRService:_vehicleFromHit(hit: BasePart): Model?
	local current: Instance? = hit
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

function ANPRService:_scan(sensor: BasePart, hit: BasePart)
	local model = self:_vehicleFromHit(hit)
	if not model then
		return
	end
	local registration = model:GetAttribute("RoleplayOSRegistration")
	if type(registration) ~= "string" then
		return
	end
	-- Keyed on the sensor instance itself. GetDebugId is not available to a
	-- script at game security, so the first vehicle to touch a camera raised
	-- inside the Touched handler and no plate was ever read.
	local cooldown = self.cooldowns[sensor]
	if not cooldown then
		cooldown = {
			Entries = {},
			Count = 0,
			NextSweepAt = 0,
		}
		self.cooldowns[sensor] = cooldown
	end
	local now = os.clock()
	local entries = cooldown.Entries
	if now >= cooldown.NextSweepAt then
		local count = 0
		for plate, expiresAt in entries do
			if type(expiresAt) ~= "number" or expiresAt <= now then
				entries[plate] = nil
			else
				count += 1
			end
		end
		cooldown.Count = count
		cooldown.NextSweepAt = now + self.context.Configuration.ANPR.CooldownSeconds
	end
	if (entries[registration] or 0) > now then
		return
	end

	local maximum = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.ANPR.MaximumCooldownEntriesPerSensor) or 256)
	)
	if entries[registration] == nil and cooldown.Count >= maximum then
		local oldestPlate
		local oldestExpiry = math.huge
		for plate, expiresAt in entries do
			if type(expiresAt) == "number" and expiresAt < oldestExpiry then
				oldestExpiry = expiresAt
				oldestPlate = plate
			end
		end
		if oldestPlate then
			entries[oldestPlate] = nil
			cooldown.Count = math.max(0, cooldown.Count - 1)
		end
	end
	if entries[registration] == nil then
		cooldown.Count += 1
	end
	entries[registration] = now + self.context.Configuration.ANPR.CooldownSeconds
	local vehicle =
		self.context.Services:Get("VehicleOwnershipService"):GetByRegistration(registration)
	if not vehicle then
		return
	end
	local wanted, _, warrantReason =
		self.context.Services:Get("WarrantService"):HasActiveForCharacter(vehicle.OwnerCharacterId)
	if warrantReason then
		self.context.Logger:Warning("ANPR warrant lookup failed", {
			Registration = registration,
			Error = warrantReason,
		})
		return
	end
	if not wanted then
		return
	end
	local location = sensor:GetAttribute("Location") or sensor.Name
	local call = self.context.Services:Get("CallService"):Create({
		Summary = "ANPR hit: wanted vehicle " .. registration,
		Location = location,
		-- The camera's position, not the vehicle's. A wanted vehicle is not
		-- tracked across the map: it is seen where a camera saw it, and the
		-- sighting stays at that camera even as the vehicle drives on.
		Position = MapProjection.serialise(sensor.Position),
		Priority = "Immediate",
		IncidentType = "Crime in progress",
		DepartmentIds = { "Police", "Control" },
		Source = "ANPR",
		CallerName = "Automatic Number Plate Recognition",
	})
	local payload = {
		Registration = registration,
		Location = location,
		CameraId = sensor:GetAttribute("CameraId"),
		CallId = if call then call.CallId else nil,
		DetectedAt = os.time(),
	}
	for _, player in self:_alertPlayers() do
		self.alertEvent:FireClient(player, payload)
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = 0,
		Action = "ANPR.WantedVehicleDetected",
		Target = registration,
		Metadata = { Location = location },
	})
end

function ANPRService:_watch(instance: Instance)
	if not instance:IsA("BasePart") or self.watched[instance] then
		return
	end
	-- Counted against the sensors actually being watched, not against every
	-- connection this service holds. Counting the latter meant the tag signal
	-- consumed a slot, and a sensor that was removed kept its slot forever, so
	-- a map that churned tags eventually stopped watching new cameras.
	if self.watchedCount >= self.context.Configuration.ANPR.MaximumSensors then
		return
	end
	self.watched[instance] = instance.Touched:Connect(function(hit)
		self:_scan(instance, hit)
	end)
	self.watchedCount += 1
end

function ANPRService:_unwatch(instance: Instance)
	local connection = self.watched[instance]
	if connection then
		connection:Disconnect()
		self.watched[instance] = nil
		self.watchedCount -= 1
	end
	-- The cooldowns for a camera that no longer exists are of no use to anybody
	-- and were never swept, so they accumulated one entry per plate per camera
	-- for the life of the server.
	self.cooldowns[instance] = nil
end

function ANPRService:Start()
	for _, sensor in CollectionService:GetTagged(self.context.Configuration.ANPR.SensorTag) do
		self:_watch(sensor)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(self.context.Configuration.ANPR.SensorTag)
			:Connect(function(sensor)
				self:_watch(sensor)
			end)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(self.context.Configuration.ANPR.SensorTag)
			:Connect(function(sensor)
				self:_unwatch(sensor)
			end)
	)
end

function ANPRService:Destroy()
	for instance in self.watched do
		self:_unwatch(instance)
	end
	table.clear(self.watched)
	self.watchedCount = 0
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.cooldowns)
end

return ANPRService
