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

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- The name a camera system looks for. A BindableFunction rather than a module,
-- so a script that knows nothing about RoleplayOS and cannot require anything
-- from it can still ask.
local BRIDGE_NAME = "RoleplayOSIssueFine"

local RoadSafetyService = {
	sensors = {},
	taggedSensors = {},
	cooldowns = {},
	journeys = {},
	running = false,
}

function RoadSafetyService:Init(context: any)
	self.context = context
	self.connections = {}
	self.fineEvent = context.Network:RegisterEvent("RoadSafetyFine")
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
	self:_adoptCameras()
	self:_startTaggedSensors()
end

-- Takes over every speed camera in the world.
--
-- A camera model holds a sensor part and a Configuration with a SpeedLimit,
-- which is what the camera kit builds, so they are found by that shape rather
-- than by a tag: a camera dropped into the map works with nothing else done to
-- it, and no list anywhere needs updating.
--
-- The kit's own script should be deleted from the model. This does the same job
-- and, unlike a script that can only check a team name, it knows whether the
-- driver is actually on a blue light run.
function RoadSafetyService:_adoptCameras()
	local settings = self.context.Configuration.RoadSafety
	local function consider(instance: Instance)
		if not instance:IsA("Model") then
			return
		end
		local sensor = instance:FindFirstChild(settings.SensorName)
		local configuration = instance:FindFirstChild(settings.ConfigurationName)
		local limit = configuration and configuration:FindFirstChild(settings.SpeedLimitValueName)
		if not sensor or not sensor:IsA("BasePart") or not limit then
			return
		end
		self:_disableKitScripts(instance)
		self:_watchSensor(instance, sensor :: BasePart)
	end

	-- Spawned, never blocking. Every service after this one waits for Start to
	-- return, and the endpoints are registered by the last of them, so a slow
	-- walk here is not a slow startup: it is a server that accepts no requests
	-- at all until it finishes. On a region sized map that is a long time.
	task.spawn(function()
		local scanned = 0
		for _, instance in Workspace:GetDescendants() do
			if instance:IsA("Model") then
				consider(instance)
			end
			scanned += 1
			-- Yielded periodically so the walk shares the frame rather than
			-- holding it for however long a map of this size takes.
			if scanned % 2000 == 0 then
				task.wait()
			end
		end
		local count = 0
		for _ in self.sensors do
			count += 1
		end
		self.context.Logger:Info("Speed cameras adopted", { Cameras = count })
	end)

	table.insert(
		self.connections,
		Workspace.DescendantAdded:Connect(function(instance)
			-- Filtered before anything is scheduled. This fires for every part of
			-- every model the map streams in, so deferring on all of them queues
			-- thousands of calls that will each decide they had nothing to do.
			if not instance:IsA("Model") then
				return
			end
			-- Deferred, because a model streams in a piece at a time and its
			-- sensor may not have arrived at the moment the model does.
			task.defer(consider, instance)
		end)
	)
end

-- Switches off the script the camera kit ships inside each model.
--
-- Leaving it running would fine twice, and its own attempt fails anyway: it
-- subtracts from a leaderstats value this game does not have, so it raises
-- rather than charging anybody. It also decides exemptions from a team name,
-- which cannot express the rule that matters here, since an emergency driver is
-- exempt while responding and not otherwise.
--
-- Disabled rather than destroyed, so the model is still the kit's model and the
-- change is undone by ticking one box.
function RoadSafetyService:_disableKitScripts(camera: Model)
	for _, child in camera:GetDescendants() do
		if child:IsA("Script") and not child:GetAttribute("RoleplayOSManaged") then
			child.Disabled = true
			child:SetAttribute("RoleplayOSManaged", true)
		end
	end
end

function RoadSafetyService:_watchSensor(camera: Model, sensor: BasePart)
	if self.sensors[sensor] then
		return
	end
	self.sensors[sensor] = camera:GetFullName()
	table.insert(
		self.connections,
		sensor.Touched:Connect(function(hit)
			self:_reading(camera, sensor, hit)
		end)
	)
end

-- Resolves any body part touching a sensor to the vehicle's driver seat. Camera
-- triggers normally touch a bumper, wheel or chassis first; requiring the
-- enclosed VehicleSeat itself to cross the trigger misses most realistic cars.
function RoadSafetyService:_seatFromHit(hit: BasePart): VehicleSeat?
	if hit:IsA("VehicleSeat") then
		return hit
	end
	local assembly = hit.AssemblyRootPart
	local current: Instance? = hit
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local seat = current:FindFirstChildWhichIsA("VehicleSeat", true)
			if seat and (not assembly or seat.AssemblyRootPart == assembly) then
				return seat
			end
		end
		current = current.Parent
	end
	return nil
end

-- Flashes the camera, where it has a light to flash with.
function RoadSafetyService:_flash(camera: Model)
	local settings = self.context.Configuration.RoadSafety
	local head = camera:FindFirstChild(settings.CameraPartName)
	local light = head and head:FindFirstChild(settings.LightPartName)
	if not light then
		return
	end
	task.spawn(function()
		for _ = 1, 2 do
			for _, child in light:GetChildren() do
				if child:IsA("Light") then
					child.Enabled = true
				end
			end
			task.wait(0.1)
			for _, child in light:GetChildren() do
				if child:IsA("Light") then
					child.Enabled = false
				end
			end
			task.wait(0.4)
		end
	end)
end

-- The plate written on a vehicle when it was spawned, so a fine reaches the
-- registered keeper rather than whoever happens to be behind the wheel.
function RoadSafetyService:_registrationOf(seat: BasePart): (string?, Model?)
	local model = seat:FindFirstAncestorOfClass("Model")
	local outermost = model
	while model do
		local plate = model:GetAttribute("RoleplayOSRegistration")
		if type(plate) == "string" and plate ~= "" then
			return plate, model
		end
		outermost = model
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, outermost
end

function RoadSafetyService:_reading(camera: Model, sensor: BasePart, hit: BasePart)
	local seat = self:_seatFromHit(hit)
	if not seat then
		return
	end
	-- Touched fires on an empty seat as readily as an occupied one.
	local occupant = seat.Occupant
	if not occupant then
		return
	end
	local character = occupant.Parent
	local player = if character then Players:GetPlayerFromCharacter(character) else nil
	if not player then
		return
	end

	local settings = self.context.Configuration.RoadSafety
	local now = os.clock()
	local perSensor = self.cooldowns[sensor]
	if not perSensor then
		perSensor = {}
		self.cooldowns[sensor] = perSensor
	end
	if (perSensor[seat] or 0) > now then
		return
	end

	local configuration = camera:FindFirstChild(settings.ConfigurationName)
	local limitValue = configuration and configuration:FindFirstChild(settings.SpeedLimitValueName)
	local limit = if limitValue and limitValue:IsA("ValueBase")
		then tonumber((limitValue :: any).Value)
		else nil
	if not limit or limit <= 0 then
		return
	end

	-- AssemblyLinearVelocity rather than the deprecated Velocity, converted with
	-- the same factor the rest of the framework uses for a speedometer.
	local mph = hit.AssemblyLinearVelocity.Magnitude
		* self.context.Configuration.VehicleSpawning.StudsPerSecondToMph
	if mph < limit + settings.ToleranceMph then
		return
	end
	perSensor[seat] = now + settings.SensorCooldownSeconds

	local registration, vehicle = self:_registrationOf(seat)
	local issued = self:IssueFine({
		Registration = registration,
		Mph = mph,
		LimitMph = limit,
		Vehicle = vehicle,
		Driver = player,
		CameraId = camera:GetAttribute("CameraId") or camera.Name,
		Location = camera:GetAttribute("Location") or camera.Name,
		Kind = "SpeedCamera",
	})
	-- Flashed only when somebody was actually fined. Flashing a responding
	-- ambulance and then not fining it tells the driver they were caught when
	-- they were not.
	if issued then
		self:_flash(camera)
	end
end

function RoadSafetyService:_vehicleFromPart(hit: BasePart): (Model?, VehicleSeat?, Player?)
	local seat = self:_seatFromHit(hit)
	if not seat or not seat.Occupant then
		return nil, seat, nil
	end
	local player = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
	local _, vehicle = self:_registrationOf(seat)
	return vehicle, seat, player
end

function RoadSafetyService:_taggedFixed(sensor: BasePart, hit: BasePart)
	local vehicle, seat, player = self:_vehicleFromPart(hit)
	if not vehicle or not seat or not player then
		return
	end
	local now = os.clock()
	local perSensor = self.cooldowns[sensor]
	if not perSensor then
		perSensor = {}
		self.cooldowns[sensor] = perSensor
	end
	if (perSensor[vehicle] or 0) > now then
		return
	end
	local telemetry = self.context.Services:Get("VehicleService"):GetTelemetry(vehicle)
	local mph = if telemetry
		then telemetry.SpeedMph
		else seat.AssemblyLinearVelocity.Magnitude
			* self.context.Configuration.VehicleSpawning.StudsPerSecondToMph
	local issued = self:IssueFine({
		Registration = vehicle:GetAttribute("RoleplayOSRegistration"),
		Mph = mph,
		LimitMph = sensor:GetAttribute("SpeedLimitMph") or 30,
		Vehicle = vehicle,
		Driver = player,
		CameraId = sensor:GetAttribute("CameraId") or sensor.Name,
		Location = sensor:GetAttribute("Location") or sensor.Name,
		Kind = "Fixed",
	})
	perSensor[vehicle] = now
		+ (if issued then self.context.Configuration.RoadSafety.SensorCooldownSeconds else 1)
end

function RoadSafetyService:_taggedAverage(sensor: BasePart, hit: BasePart, isEntry: boolean)
	local vehicle, _, player = self:_vehicleFromPart(hit)
	if not vehicle or not player then
		return
	end
	local registration = vehicle:GetAttribute("RoleplayOSRegistration")
	local identity = if type(registration) == "string" and registration ~= ""
		then registration
		else "driver:" .. tostring(player.UserId)
	local corridor = sensor:GetAttribute("CorridorId") or "Default"
	local key = identity .. ":" .. tostring(corridor)
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
		* self.context.Configuration.VehicleSpawning.StudsPerSecondToMph
	self:IssueFine({
		Registration = registration,
		Mph = mph,
		LimitMph = sensor:GetAttribute("SpeedLimitMph") or 30,
		Vehicle = vehicle,
		Driver = player,
		CameraId = sensor:GetAttribute("CameraId") or sensor.Name,
		Location = sensor:GetAttribute("Location") or sensor.Name,
		Kind = "Average",
	})
end

function RoadSafetyService:_connectTag(tag: string, callback: (BasePart, BasePart) -> ())
	local function watch(instance: Instance)
		if
			not instance:IsA("BasePart")
			or self.taggedSensors[instance]
			or self.sensors[instance]
		then
			return
		end
		self.taggedSensors[instance] = instance.Touched:Connect(function(hit)
			callback(instance, hit)
		end)
	end
	local function unwatch(instance: Instance)
		local connection = self.taggedSensors[instance]
		if connection then
			connection:Disconnect()
			self.taggedSensors[instance] = nil
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		watch(instance)
	end
	table.insert(self.connections, CollectionService:GetInstanceAddedSignal(tag):Connect(watch))
	table.insert(self.connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatch))
end

function RoadSafetyService:_startTaggedSensors()
	local settings = self.context.Configuration.RoadSafety
	self:_connectTag(settings.SpeedCameraTag, function(sensor, hit)
		self:_taggedFixed(sensor, hit)
	end)
	self:_connectTag(settings.AverageEntryTag, function(sensor, hit)
		self:_taggedAverage(sensor, hit, true)
	end)
	self:_connectTag(settings.AverageExitTag, function(sensor, hit)
		self:_taggedAverage(sensor, hit, false)
	end)
	self.running = true
	task.spawn(function()
		while self.running do
			task.wait(settings.StateCleanupSeconds)
			local now = os.clock()
			for sensor, perSensor in self.cooldowns do
				for vehicle, expiresAt in perSensor do
					if expiresAt <= now then
						perSensor[vehicle] = nil
					end
				end
				if next(perSensor) == nil then
					self.cooldowns[sensor] = nil
				end
			end
			for key, journey in self.journeys do
				if now - journey.Time > settings.AverageJourneyExpirySeconds then
					self.journeys[key] = nil
				end
			end
		end
	end)
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
-- Whether a name looks like it belongs to the blue lights.
--
-- Exclusions are checked first, so a headlight, a brake light or an interior
-- lamp is never mistaken for a response. Without that, a marked car simply
-- driving at night would be exempt from every camera in the map.
function RoadSafetyService:_nameLooksLikeLights(name: string): boolean
	local settings = self.context.Configuration.EmergencyLights
	local lowered = string.lower(name)
	for _, excluded in settings.ExcludedPatterns do
		if string.find(lowered, excluded, 1, true) then
			return false
		end
	end
	for _, pattern in settings.NamePatterns do
		if string.find(lowered, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Reports the first thing that read as on, once per name.
--
-- The exact attribute a lighting system sets cannot be known from here, so this
-- says what it actually matched. That turns "the exemption is not firing" from
-- guesswork into a line in the log naming the thing to put in AttributeNames.
function RoadSafetyService:_noteMatch(where: string, name: string)
	self.noted = self.noted or {}
	if self.noted[name] then
		return
	end
	self.noted[name] = true
	self.context.Logger:Info("Emergency lights read from", { Source = where, Name = name })
end

function RoadSafetyService:AreLightsOn(vehicle: Instance?): boolean
	if not vehicle then
		return false
	end
	-- The authoritative answer first.
	--
	-- Where this framework owns the lighting it set this attribute itself, so
	-- there is nothing to infer and no fork to be wrong about. Everything below
	-- is the fallback for a vehicle still running a third party kit, and it is
	-- guesswork: it exists because two different kits in this place disagree
	-- about where the state lives, and guessing wrong costs an emergency driver
	-- a fine.
	local owned = self.context.Configuration.EmergencyLighting
	if owned and owned.Enabled then
		local state = vehicle:GetAttribute(owned.StateAttribute)
		if type(state) == "boolean" then
			return state
		end
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
				self:_noteMatch("attribute", name)
				return true
			end
		end
		-- Then anything whose name looks like it belongs to the blue lights, so a
		-- system nobody here has seen still works without being configured first.
		for name, value in root:GetAttributes() do
			if self:_nameLooksLikeLights(name) and self:_readsAsOn(value) then
				self:_noteMatch("attribute", name)
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
					self:_noteMatch("value", name)
					return true
				end
			end
			for _, item in folder:GetChildren() do
				if
					item:IsA("ValueBase")
					and self:_nameLooksLikeLights(item.Name)
					and self:_readsAsOn((item :: any).Value)
				then
					self:_noteMatch("value", item.Name)
					return true
				end
			end
		end
	end

	-- Last, any value anywhere in the vehicle whose name looks right. Lighting
	-- systems put these wherever they like, and a vehicle is small enough that
	-- looking through it costs nothing next to being wrong.
	for _, item in vehicle:GetDescendants() do
		if
			item:IsA("ValueBase")
			and self:_nameLooksLikeLights(item.Name)
			and self:_readsAsOn((item :: any).Value)
		then
			self:_noteMatch("descendant", item.Name)
			return true
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
	local driver = request.Driver
	local hasDriver = typeof(driver) == "Instance" and driver:IsA("Player")
	if (type(registration) ~= "string" or registration == "") and not hasDriver then
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

	-- The registered keeper where the plate resolves to one, and the person at
	-- the wheel otherwise. A camera can read a plate off a civilian's own car,
	-- but a service vehicle belongs to nobody and somebody should still answer
	-- for driving it at seventy through a thirty.
	local player, character = nil, nil
	if type(registration) == "string" and registration ~= "" then
		player, character = self:_keeper(registration)
	end
	if not player and hasDriver then
		player = driver
		local session = self.context.Services:Get("DataService"):GetSession(driver)
		local characterId = session and session.ActiveCharacterId
		character = characterId and session.Profile.Characters[characterId]
	end
	if not player or not character then
		return false, "KEEPER_UNAVAILABLE"
	end

	-- Judged against whoever is driving, which is not necessarily the keeper: an
	-- officer on a response in a car registered to somebody else is still on a
	-- response, and the keeper should not be fined for it.
	if self:IsExempt(if hasDriver then driver else player, request.Vehicle) then
		return false, "EXEMPT_EMERGENCY_RESPONSE"
	end

	local points = self:_points(excess)
	local fine = math.min(settings.MaximumFine, settings.FineBase + excess * settings.FinePerMph)
	local issuingOfficer = request.IssuingOfficer
	local officerName, officerRank = nil, nil
	if
		typeof(issuingOfficer) == "Instance"
		and issuingOfficer:IsA("Player")
		and issuingOfficer.Parent == Players
	then
		local duty = self.context.Services:Get("DutyService"):Get(issuingOfficer)
		if duty and duty.DepartmentId == "Police" then
			local officerSession =
				self.context.Services:Get("DataService"):GetSession(issuingOfficer)
			local profile = officerSession
				and officerSession.Profile.DutyProfiles[duty.DutyProfileId]
			officerName = issuingOfficer.Name
			officerRank = self.context.Services
				:Get("DepartmentService")
				:GetRankName("Police", if profile then tonumber(profile.Rank) or 1 else 1)
		end
	end
	local record = {
		FineId = HttpService:GenerateGUID(false),
		IssuedAt = os.time(),
		Registration = if type(registration) == "string" and registration ~= ""
			then registration
			else "UNREGISTERED",
		CameraId = if type(request.CameraId) == "string" and request.CameraId ~= ""
			then request.CameraId
			else "UNKNOWN",
		Location = if type(request.Location) == "string" then request.Location else "Speed camera",
		Type = if type(request.Kind) == "string" then request.Kind else "SpeedCamera",
		RecordedMph = math.floor(speed + 0.5),
		LimitMph = math.floor(allowed + 0.5),
		Fine = fine,
		Points = points,
		Status = "Unpaid",
		Driver = player.Name,
		DriverUserId = player.UserId,
		IssuingDepartment = self.context.Configuration.Integrations.Discord.SpeedingFines.DepartmentName,
		IssuingOfficer = officerName,
		IssuingOfficerRank = officerRank,
	}

	character.DrivingRecord = character.DrivingRecord or { Points = 0, Fines = {} }
	character.DrivingRecord.Fines = character.DrivingRecord.Fines or {}
	if settings.AutomaticallyDebitFines then
		local paid, paymentReason = self.context.Services:Get("EconomyService"):Apply(player, {
			TransactionId = "speed-camera:" .. record.FineId,
			CharacterId = character.CharacterId,
			Direction = "Debit",
			Amount = fine,
			ReasonCode = "SPEED_CAMERA_FINE",
			RelatedEntityId = record.FineId,
			Metadata = {
				CameraId = record.CameraId,
				Registration = record.Registration,
				RecordedMph = record.RecordedMph,
				LimitMph = record.LimitMph,
			},
		})
		if paid then
			record.Status = "Paid"
			record.PaidAt = os.time()
		else
			record.PaymentFailureCode = paymentReason
		end
	end
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
	self.fineEvent:FireClient(player, {
		Fine = record.Fine,
		Points = record.Points,
		RecordedMph = record.RecordedMph,
		LimitMph = record.LimitMph,
		Status = record.Status,
	})
	-- External reporting is queued after persistence and never participates in
	-- whether the fine succeeds. Automatic cameras are labelled as such; a
	-- police-issued request can pass IssuingOfficer for the officer and rank.
	self.context.Services:Get("DiscordFineService"):Enqueue(record, issuingOfficer)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = 0,
		Action = "RoadSafety.OffenceIssued",
		Target = character.CharacterId,
		Metadata = record,
	})
	return true, nil
end

function RoadSafetyService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.taggedSensors do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.sensors)
	table.clear(self.taggedSensors)
	table.clear(self.cooldowns)
	table.clear(self.journeys)
	if self.bridge then
		self.bridge:Destroy()
		self.bridge = nil
	end
end

return RoadSafetyService
