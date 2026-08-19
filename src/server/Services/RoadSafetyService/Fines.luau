--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

return function(RoadSafetyService)
	-- The penalty for how far over the limit somebody was.
	--
	-- Ordered, so the first band the excess falls inside wins, and the last has no
	-- ceiling so there is always an answer. Returning the whole band rather than
	-- the points alone keeps the fine and the points from being decided in two
	-- different places by two different rules.
	function RoadSafetyService:_band(excess: number): any
		local bands = self.context.Configuration.RoadSafety.PenaltyBands
		for _, band in bands do
			if excess <= band.MaximumExcessMph then
				return band
			end
		end
		return bands[#bands]
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

		local band = self:_band(excess)
		local points = band.Points
		local fine = band.Fine
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
				officerRank = self.context.Services:Get("DepartmentService"):GetRankName(
					"Police",
					if profile then tonumber(profile.Rank) or 1 else 1
				)
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
			Location = if type(request.Location) == "string"
				then request.Location
				else "Speed camera",
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
		character.DrivingRecord.Points =
			math.min(99, (character.DrivingRecord.Points or 0) + points)

		self.context.Services:Get("DataService"):MarkDirty(player)
		-- Person only. A fine changes the driving record and nothing about the cars,
		-- and rewriting the fleet alongside it cost eleven DataStore writes per
		-- camera flash out of a server budget of roughly six a second.
		self.context.Services
			:Get("RecordIndexService")
			:ScheduleCharacter(player, character, "Person")
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
end
