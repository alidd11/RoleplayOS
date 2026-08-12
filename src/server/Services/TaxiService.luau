--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local TaxiService = { requests = {}, byPassenger = {}, byDriver = {} }

function TaxiService:Init(context: any)
	self.context = context
	self.phone = context.Services:Get("PhoneService")
	self.settings = context.Configuration.Taxi
	self.connections = {}
end

function TaxiService:_character(player: Player): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session or not session.ActiveCharacterId then
		return nil, "ACTIVE_CHARACTER_REQUIRED"
	end
	local character = session.Profile.Characters[session.ActiveCharacterId]
	if not character then
		return nil, "ACTIVE_CHARACTER_REQUIRED"
	end
	return character, session.ActiveCharacterId
end

function TaxiService:_isDriver(player: Player): boolean
	if not player.Parent then
		return false
	end
	-- A TaxiDriver employment is the durable job credential. The Transport team
	-- is also accepted for servers that use department teams for their taxi fleet.
	if player.Team and (player.Team.Name == "Taxi" or player.Team.Name == "Transport") then
		return true
	end
	local character = self:_character(player)
	for _, employment in character and character.Employment or {} do
		if employment.JobId == "TaxiDriver" and not employment.EndedAt then
			return true
		end
	end
	return false
end

function TaxiService:IsDriver(player: Player): boolean
	return self:_isDriver(player)
end

function TaxiService:_notify(player: Player, message: any)
	local character = self:_character(player)
	if character then
		self.phone:AppendSystemMessage(player, character, message)
	end
end

function TaxiService:_statusFor(player: Player): any?
	local id = self.byPassenger[player.UserId] or self.byDriver[player.UserId]
	local request = id and self.requests[id]
	if not request then
		return nil
	end
	return {
		RequestId = request.RequestId,
		State = request.State,
		Pickup = request.Pickup,
		Dropoff = request.Dropoff,
		Fare = request.Fare,
		Band = request.Band,
		PickupPosition = request.PickupPosition,
		PassengerName = request.PassengerName,
		DriverName = request.DriverName,
		IsDriver = request.DriverUserId == player.UserId,
		CreatedAt = request.CreatedAt,
	}
end

function TaxiService:StartShift(player: Player): (any?, string?)
	local character, characterId = self:_character(player)
	if not character then
		return nil, characterId
	end
	if self:_isDriver(player) then
		return self:_statusFor(player) or { State = "OnDuty" }, nil
	end
	local employment =
		self.context.Services:Get("EmploymentService"):Hire(player, characterId, "TaxiDriver")
	if not employment then
		return nil, "TAXI_JOB_UNAVAILABLE"
	end
	local transportTeam = self.context.Services:Get("TeamService"):Get("Transport")
	if not transportTeam then
		return nil, "TRANSPORT_TEAM_UNAVAILABLE"
	end
	-- Taxi is a civilian employment, but its operational base and character
	-- spawn are the shared Transport depot. Reusing that department keeps the
	-- player aligned with the one Transport fleet facility and avoids a second
	-- taxi-only spawn pad/team route.
	player.Team = transportTeam
	self.context.Services:Get("DataService"):MarkDirty(player)
	return { State = "OnDuty", EmploymentId = employment.EmploymentId }, nil
end

function TaxiService:EndShift(player: Player): (boolean, string?)
	if self.byDriver[player.UserId] then
		return false, "TAXI_REQUEST_ACTIVE"
	end
	local character = self:_character(player)
	if not character then
		return false, "ACTIVE_CHARACTER_REQUIRED"
	end
	for index = #character.Employment, 1, -1 do
		local employment = character.Employment[index]
		if employment.JobId == "TaxiDriver" and not employment.EndedAt then
			employment.EndedAt = os.time()
			break
		end
	end
	local civilian = self.context.Services:Get("TeamService"):Get("Civilian")
	if civilian then
		player.Team = civilian
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	return true, nil
end

function TaxiService:GetStatus(player: Player): any?
	return self:_statusFor(player)
end

function TaxiService:GetDriverRequest(player: Player): any?
	if not self:_isDriver(player) or self.byDriver[player.UserId] then
		return nil
	end
	for _, request in self.requests do
		if request.State == "Waiting" then
			return {
				RequestId = request.RequestId,
				State = request.State,
				Pickup = request.Pickup,
				Dropoff = request.Dropoff,
				Fare = request.Fare,
				Band = request.Band,
				PassengerName = request.PassengerName,
				CreatedAt = request.CreatedAt,
			}
		end
	end
	return nil
end

function TaxiService:_activeTaxi(player: Player): Model?
	local vehicleService = self.context.Services:Get("VehicleSpawnerService")
	local vehicle = vehicleService and vehicleService.active[player.UserId]
	if not vehicle or not vehicle:IsA("Model") or not vehicle.Parent then
		return nil
	end
	if vehicle:GetAttribute("RoleplayOSDefinitionId") ~= "CorollaTaxi" then
		return nil
	end
	return vehicle
end

function TaxiService:_isSeatedInTaxi(player: Player, vehicle: Model): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	for _, seat in vehicle:GetDescendants() do
		if (seat:IsA("Seat") or seat:IsA("VehicleSeat")) and seat.Occupant == humanoid then
			return true
		end
	end
	return false
end

function TaxiService:_fare(band: any): (number?, string?)
	if type(band) ~= "string" then
		return nil, "INVALID_FARE_BAND"
	end
	local definition = self.settings.Bands[band]
	if not definition then
		return nil, "INVALID_FARE_BAND"
	end
	return definition.Fare, nil
end

function TaxiService:Request(
	player: Player,
	rawPickup: any,
	rawDropoff: any,
	rawBand: any
): (any?, string?)
	if player.Team == nil or player.Team.Name ~= "Civilian" then
		return nil, "CIVILIAN_REQUIRED"
	end
	if self.byPassenger[player.UserId] or self.byDriver[player.UserId] then
		return nil, "TAXI_REQUEST_ALREADY_ACTIVE"
	end
	local character, characterId = self:_character(player)
	if not character then
		return nil, characterId
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, "CHARACTER_NOT_READY"
	end
	if type(rawPickup) ~= "string" or #rawPickup < 2 or #rawPickup > 80 then
		return nil, "INVALID_PICKUP"
	end
	if type(rawDropoff) ~= "string" or #rawDropoff < 2 or #rawDropoff > 80 then
		return nil, "INVALID_DROPOFF"
	end
	local fare, fareReason = self:_fare(rawBand)
	if not fare then
		return nil, fareReason
	end
	if character.Economy.Balance < fare then
		return nil, "INSUFFICIENT_FUNDS"
	end
	local pickup, pickupReason =
		TextFilter.forBroadcast(rawPickup, player.UserId, Enum.TextFilterContext.PublicChat)
	local dropoff, dropoffReason =
		TextFilter.forBroadcast(rawDropoff, player.UserId, Enum.TextFilterContext.PublicChat)
	if not pickup then
		return nil, pickupReason
	end
	if not dropoff then
		return nil, dropoffReason
	end
	local identity = character.Identity.FirstName .. " " .. character.Identity.LastName
	local request = {
		RequestId = HttpService:GenerateGUID(false),
		PassengerUserId = player.UserId,
		PassengerCharacterId = characterId,
		PassengerName = identity,
		Pickup = pickup,
		Dropoff = dropoff,
		Band = rawBand,
		Fare = fare,
		PickupPosition = root.Position,
		State = "Waiting",
		CreatedAt = os.time(),
	}
	self.requests[request.RequestId] = request
	self.byPassenger[player.UserId] = request.RequestId
	for _, driver in Players:GetPlayers() do
		if driver ~= player and self:_isDriver(driver) then
			self:_notify(driver, {
				Kind = "TaxiRequest",
				MessageId = request.RequestId,
				Direction = "Incoming",
				Body = string.format("Taxi request · %s → %s · £%d", pickup, dropoff, fare),
				Pickup = pickup,
				Dropoff = dropoff,
				Fare = fare,
				TaxiId = request.RequestId,
				Timestamp = request.CreatedAt,
			})
		end
	end
	return self:_statusFor(player), nil
end

function TaxiService:Accept(player: Player, requestId: any): (any?, string?)
	if type(requestId) ~= "string" or not self:_isDriver(player) then
		return nil, "TAXI_DRIVER_REQUIRED"
	end
	if self.byDriver[player.UserId] then
		return nil, "TAXI_REQUEST_ALREADY_ACTIVE"
	end
	local request = self.requests[requestId]
	if not request or request.State ~= "Waiting" then
		return nil, "TAXI_REQUEST_UNAVAILABLE"
	end
	local driverCharacter = self:_character(player)
	if not driverCharacter then
		return nil, "ACTIVE_CHARACTER_REQUIRED"
	end
	local vehicle = self:_activeTaxi(player)
	if not vehicle then
		return nil, "TAXI_VEHICLE_REQUIRED"
	end
	request.State = "Accepted"
	request.DriverUserId = player.UserId
	request.DriverCharacterId = driverCharacter.CharacterId
	request.DriverName = driverCharacter.Identity.FirstName
		.. " "
		.. driverCharacter.Identity.LastName
	request.AcceptedPosition = vehicle:GetPivot().Position
	self.byDriver[player.UserId] = requestId
	local passenger = Players:GetPlayerByUserId(request.PassengerUserId)
	if passenger then
		self:_notify(passenger, {
			Kind = "TaxiStatus",
			MessageId = requestId,
			Direction = "Incoming",
			Body = "Taxi accepted · " .. request.DriverName .. " is on the way",
			TaxiId = requestId,
			Timestamp = os.time(),
		})
	end
	return self:_statusFor(player), nil
end

function TaxiService:Complete(player: Player, requestId: any): (any?, string?)
	if type(requestId) ~= "string" or self.byDriver[player.UserId] ~= requestId then
		return nil, "TAXI_DRIVER_REQUIRED"
	end
	local request = self.requests[requestId]
	if not request or request.State ~= "Accepted" then
		return nil, "TAXI_REQUEST_UNAVAILABLE"
	end
	local passenger = Players:GetPlayerByUserId(request.PassengerUserId)
	if not passenger then
		return nil, "PASSENGER_UNAVAILABLE"
	end
	local passengerCharacter, passengerCharacterId = self:_character(passenger)
	local driverCharacter, driverCharacterId = self:_character(player)
	if not passengerCharacter or not driverCharacter then
		return nil, "ACTIVE_CHARACTER_REQUIRED"
	end
	if
		passengerCharacterId ~= request.PassengerCharacterId
		or driverCharacterId ~= request.DriverCharacterId
	then
		return nil, "CHARACTER_CHANGED"
	end
	local vehicle = self:_activeTaxi(player)
	if
		not vehicle
		or not self:_isSeatedInTaxi(player, vehicle)
		or not self:_isSeatedInTaxi(passenger, vehicle)
	then
		return nil, "TAXI_OCCUPANTS_REQUIRED"
	end
	local journeyDistance = (vehicle:GetPivot().Position - request.PickupPosition).Magnitude
	local minimumDistance = tonumber(self.settings.MinimumJourneyStuds) or 60
	if journeyDistance < minimumDistance then
		return nil, "TAXI_JOURNEY_NOT_COMPLETED"
	end
	if passengerCharacter.Economy.Balance < request.Fare then
		return nil, "INSUFFICIENT_FUNDS"
	end
	local economy = self.context.Services:Get("EconomyService")
	local transferId = HttpService:GenerateGUID(false)
	local debited, debitReason = economy:Apply(passenger, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = passengerCharacterId,
		Amount = request.Fare,
		Direction = "Debit",
		ReasonCode = "TAXI_FARE",
		Description = "Taxi fare to " .. request.Dropoff,
		RelatedEntityId = transferId,
		Metadata = { TaxiId = requestId, DriverUserId = player.UserId },
	})
	if not debited then
		return nil, debitReason
	end
	local credited, creditReason = economy:Apply(player, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = driverCharacterId,
		Amount = request.Fare,
		Direction = "Credit",
		ReasonCode = "TAXI_FARE_RECEIVED",
		Description = "Taxi fare from " .. request.PassengerName,
		RelatedEntityId = transferId,
		Metadata = { TaxiId = requestId, PassengerUserId = passenger.UserId },
	})
	if not credited then
		economy:Apply(passenger, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = passengerCharacterId,
			Amount = request.Fare,
			Direction = "Credit",
			ReasonCode = "TAXI_FARE_REFUND",
			Description = "Taxi fare refund",
			RelatedEntityId = transferId,
			Metadata = { TaxiId = requestId },
		})
		return nil, creditReason
	end
	request.State = "Completed"
	request.CompletedAt = os.time()
	self.byPassenger[request.PassengerUserId] = nil
	self.byDriver[player.UserId] = nil
	self:_notify(passenger, {
		Kind = "TaxiStatus",
		MessageId = requestId,
		Direction = "Incoming",
		Body = string.format("Taxi complete · %s paid £%d", request.DriverName, request.Fare),
		TaxiId = requestId,
		Timestamp = os.time(),
	})
	return { Fare = request.Fare, RequestId = requestId }, nil
end

function TaxiService:Cancel(player: Player, requestId: any): (boolean, string?)
	if type(requestId) ~= "string" then
		return false, "INVALID_TAXI_REQUEST"
	end
	local request = self.requests[requestId]
	if
		not request
		or (request.PassengerUserId ~= player.UserId and request.DriverUserId ~= player.UserId)
	then
		return false, "TAXI_REQUEST_UNAVAILABLE"
	end
	if request.State == "Completed" then
		return false, "TAXI_REQUEST_UNAVAILABLE"
	end
	request.State = "Cancelled"
	self.byPassenger[request.PassengerUserId] = nil
	if request.DriverUserId then
		self.byDriver[request.DriverUserId] = nil
	end
	local other = Players:GetPlayerByUserId(
		if request.PassengerUserId == player.UserId
			then request.DriverUserId
			else request.PassengerUserId
	)
	if other then
		self:_notify(other, {
			Kind = "TaxiStatus",
			MessageId = requestId,
			Direction = "Incoming",
			Body = "Taxi request cancelled",
			TaxiId = requestId,
			Timestamp = os.time(),
		})
	end
	return true, nil
end

function TaxiService:Start()
	self.running = true
	task.spawn(function()
		while self.running do
			task.wait(60)
			local cutoff = os.time() - (tonumber(self.settings.RequestRetentionSeconds) or 900)
			for requestId, request in self.requests do
				local terminal = request.State == "Completed" or request.State == "Cancelled"
				local timestamp = tonumber(request.CompletedAt or request.CreatedAt) or os.time()
				if terminal and timestamp < cutoff then
					self.requests[requestId] = nil
				end
			end
		end
	end)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			local requestId = self.byPassenger[player.UserId] or self.byDriver[player.UserId]
			if requestId then
				self:Cancel(player, requestId)
			end
		end)
	)
end

function TaxiService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.requests)
	table.clear(self.byPassenger)
	table.clear(self.byDriver)
end

return TaxiService
