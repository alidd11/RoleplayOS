--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

return function(RoadSafetyService)
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
			local limit = configuration
				and configuration:FindFirstChild(settings.SpeedLimitValueName)
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
		sensor.CanCollide = false
		sensor.CanTouch = true
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
	-- Which vehicle seat a touched part belongs to, remembered per assembly.
	--
	-- Touched fires for every part that brushes a sensor, so a car crossing one
	-- raises it dozens of times: each wheel, the bumper, every panel, entering and
	-- again leaving. This walked the ancestor chain on every one of those and asked
	-- each Model for a descendant of a class, which is a full recursive scan of a
	-- two hundred part vehicle. The cooldown that exists to stop the repeated work
	-- is checked by the caller afterwards, so it never prevented any of it.
	--
	-- Every part of one vehicle shares an assembly root, so the answer is the same
	-- for all of them and is worth keeping. The table is weak keyed, so a despawned
	-- vehicle drops out on its own rather than being held alive by having once
	-- driven past a camera.
	--
	-- A miss is remembered too, as false rather than nil, because the parts that
	-- are not vehicles are the ones that touch sensors most: pedestrians, dropped
	-- tools, the road itself.
	function RoadSafetyService:_seatFromHit(hit: BasePart): VehicleSeat?
		local assembly: Instance = hit.AssemblyRootPart or hit
		local remembered = self.seatByAssembly[assembly]
		if remembered ~= nil then
			-- A remembered seat that has since been destroyed is re-resolved rather
			-- than returned, so a respawned vehicle is not reported as the old one.
			if remembered == false then
				return nil
			end
			if (remembered :: VehicleSeat).Parent then
				return remembered :: VehicleSeat
			end
		end
		local found: VehicleSeat? = nil
		if hit:IsA("VehicleSeat") then
			found = hit
		else
			local current: Instance? = hit
			while current and current ~= Workspace do
				if current:IsA("Model") then
					local seat = current:FindFirstChildWhichIsA("VehicleSeat", true)
					if seat then
						found = seat :: VehicleSeat
						break
					end
				end
				current = current.Parent
			end
		end
		self.seatByAssembly[assembly] = found or false
		return found
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

	-- A-Chassis publishes horizontal velocity in Values.Velocity. Prefer that
	-- value, matching the speedometer, and fall back to the seat for plain Roblox
	-- vehicles. AssemblyLinearVelocity.Magnitude includes jumps and suspension
	-- bounce, which could otherwise trigger a camera while the vehicle is not
	-- actually travelling faster along the road.
	function RoadSafetyService:_speedMph(seat: VehicleSeat): number
		local values =
			seat:FindFirstChild(self.context.Configuration.Chassis.ValuesFolderName, true)
		local published = nil
		for _, name in self.context.Configuration.Chassis.VelocityValueNames or {} do
			local item = values and values:FindFirstChild(name)
			if item and item:IsA("Vector3Value") then
				published = item.Value
				break
			end
		end
		local velocity = if typeof(published) == "Vector3"
			then published
			else seat.AssemblyLinearVelocity
		return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			* self.context.Configuration.VehicleData.StudsPerSecondToMph
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
		local limitValue = configuration
			and configuration:FindFirstChild(settings.SpeedLimitValueName)
		local limit = if limitValue and limitValue:IsA("ValueBase")
			then tonumber((limitValue :: any).Value)
			else nil
		if not limit or limit <= 0 then
			return
		end

		-- Prefer the server's validated vehicle telemetry. Imported chassis often
		-- split wheels and bodywork into separate assemblies, so the first touched
		-- part can report a very different velocity from the actual vehicle.
		local registration, vehicle = self:_registrationOf(seat)
		local mph = self:_speedMph(seat)
		if mph < limit + settings.ToleranceMph then
			return
		end
		perSensor[seat] = now + settings.SensorCooldownSeconds

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
		local mph = self:_speedMph(seat)
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
			* self.context.Configuration.VehicleData.StudsPerSecondToMph
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
		table.insert(
			self.connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatch)
		)
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
end
