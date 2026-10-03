--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapProjection = require(ReplicatedStorage.RoleplayOS.Shared.MapProjection)
local ANPRService = {
	connections = {},
	cooldowns = {},
	watched = {},
	watchedCount = 0,
	running = false,
}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

function ANPRService:_isCurrentWatch(sensor: BasePart, token: any): boolean
	local state = self.watched[sensor]
	return self.running
		and state ~= nil
		and state.Token == token
		and sensor:IsDescendantOf(workspace)
end

function ANPRService:Init(context: any)
	self.context = context
	self.alertEvent = context.Network:RegisterEvent("ANPRAlert")
	self.connections = {}
	self.cooldowns = {}
	self.watched = {}
	self.watchedCount = 0
	self.running = false
end

function ANPRService:_alertPlayers(sensor: BasePart, token: any): { Player }?
	local result = {}
	if not self:_isCurrentWatch(sensor, token) then
		return nil
	end
	local dutyService = self.context.Services:Get("DutyService")
	-- ANPR alerts can only ever reach on-duty Roads Policing or Control users.
	-- Snapshot that bounded candidate set rather than walking every civilian for
	-- every wanted-plate hit. Get below remains the authority check and may yield.
	for _, userId in dutyService:ActiveUserIds() do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end
		local duty = dutyService:Get(player)
		-- DutyService:Get can yield on group access. Do not resume a stale ANPR
		-- notification pass after teardown or after this sensor was untagged and
		-- re-tagged under a new watch generation.
		if not self:_isCurrentWatch(sensor, token) then
			return nil
		end
		if
			playerIsCurrent(player)
			and duty
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

function ANPRService:_scan(sensor: BasePart, hit: BasePart, token: any)
	if not self:_isCurrentWatch(sensor, token) then
		return
	end
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
	local perSensor = self.cooldowns[sensor]
	if not perSensor then
		perSensor = {}
		self.cooldowns[sensor] = perSensor
	end
	local now = os.clock()
	local count = 0
	local oldestPlate: string? = nil
	local oldestExpiry = math.huge
	-- Expired registrations have no future purpose. Sweep them lazily on the
	-- next camera touch so a long-running sensor retains only plates seen within
	-- the current cooldown window instead of every registration it has ever seen.
	for plate, expiresAt in perSensor do
		if type(expiresAt) ~= "number" or expiresAt <= now then
			perSensor[plate] = nil
		else
			count += 1
			if expiresAt < oldestExpiry then
				oldestExpiry = expiresAt
				oldestPlate = plate
			end
		end
	end
	if (perSensor[registration] or 0) > now then
		return
	end
	local maximumCooldownRegistrations = math.max(
		1,
		math.floor(
			tonumber(self.context.Configuration.ANPR.MaximumCooldownRegistrationsPerSensor) or 256
		)
	)
	if count >= maximumCooldownRegistrations and oldestPlate then
		perSensor[oldestPlate] = nil
	end
	local cooldownExpiresAt = now + self.context.Configuration.ANPR.CooldownSeconds
	perSensor[registration] = cooldownExpiresAt
	local vehicle =
		self.context.Services:Get("VehicleOwnershipService"):GetByRegistration(registration)
	if not vehicle then
		return
	end
	local wanted, _, warrantReason =
		self.context.Services:Get("WarrantService"):HasActiveForCharacter(vehicle.OwnerCharacterId)
	-- Warrant refresh can yield through durable person-record recovery. A sensor
	-- may be untagged or this service destroyed while that lookup is in flight.
	if not self:_isCurrentWatch(sensor, token) then
		return
	end
	if warrantReason then
		-- This was not a completed scan. Keep a short retry backoff to avoid a
		-- DataStore retry storm, but do not suppress another camera touch for the
		-- full duplicate-alert cooldown after a transient warrant-store failure.
		-- Only shorten the reservation this scan created; an untagged/re-tagged
		-- sensor or a newer reservation must remain untouched.
		if self.cooldowns[sensor] == perSensor and perSensor[registration] == cooldownExpiresAt then
			local retryCooldown = math.min(self.context.Configuration.ANPR.CooldownSeconds, 3)
			perSensor[registration] = math.min(cooldownExpiresAt, os.clock() + retryCooldown)
		end
		self.context.Logger:Warning("ANPR warrant lookup failed", {
			Registration = registration,
			Error = warrantReason,
		})
		return
	end
	if not wanted then
		return
	end
	-- Resolve recipients before creating the dispatch call. Duty lookup can
	-- yield, so this keeps all externally visible hit side effects behind the
	-- final watch-generation revalidation.
	local alertPlayers = self:_alertPlayers(sensor, token)
	if not alertPlayers or not self:_isCurrentWatch(sensor, token) then
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
	for _, player in alertPlayers do
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
	if not self.running or not instance:IsA("BasePart") or self.watched[instance] then
		return
	end
	-- Counted against the sensors actually being watched, not against every
	-- connection this service holds. Counting the latter meant the tag signal
	-- consumed a slot, and a sensor that was removed kept its slot forever, so
	-- a map that churned tags eventually stopped watching new cameras.
	if self.watchedCount >= self.context.Configuration.ANPR.MaximumSensors then
		return
	end
	local token = {}
	local connection = instance.Touched:Connect(function(hit)
		self:_scan(instance, hit, token)
	end)
	self.watched[instance] = {
		Connection = connection,
		Token = token,
	}
	self.watchedCount += 1
end

function ANPRService:_unwatch(instance: Instance)
	local state = self.watched[instance]
	if state then
		state.Connection:Disconnect()
		self.watched[instance] = nil
		self.watchedCount -= 1
	end
	-- The cooldowns for a camera that no longer exists are of no use to anybody
	-- and were never swept, so they accumulated one entry per plate per camera
	-- for the life of the server.
	self.cooldowns[instance] = nil
end

function ANPRService:Start()
	self.running = true
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
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	local watched = {}
	for instance in self.watched do
		table.insert(watched, instance)
	end
	for _, instance in watched do
		self:_unwatch(instance)
	end
	table.clear(self.watched)
	self.watchedCount = 0
	table.clear(self.cooldowns)
end

return ANPRService
