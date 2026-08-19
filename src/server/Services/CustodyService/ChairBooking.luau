--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)
local root = Utils.root
local humanoid = Utils.humanoid
local trimToMaximum = Utils.trimToMaximum

return function(CustodyService)
	-- Seated in a tagged custody chair, not merely standing near one. Booking used
	-- to require standing near a RoleplayOSCustodyDesk part, a distance nobody
	-- could see the edge of; sitting a cuffed detainee down is a deliberate,
	-- visible act instead, and now the only thing Book checks for.
	function CustodyService:_seatedInChair(target: Player): boolean
		local targetHumanoid = humanoid(target)
		local seat = targetHumanoid and targetHumanoid.SeatPart
		return seat ~= nil and seat:HasTag(self.context.Configuration.Custody.ChairTag)
	end

	function CustodyService:_chairOccupant(chair: Instance): Player?
		local seat = if chair:IsA("Seat") then chair else chair:FindFirstChildWhichIsA("Seat")
		local occupant = seat and seat.Occupant
		local model = occupant and occupant.Parent
		return if model then Players:GetPlayerFromCharacter(model) else nil
	end

	-- Opens the custody actions panel for whoever is sitting in a chair, the way
	-- the panel already reopens when the cuffs are used again on someone already
	-- wearing them. This is the E-prompt path onto the same panel rather than a
	-- parallel one, so every action on it behaves exactly as it already does.
	function CustodyService:_processChair(actor: Player, chair: Instance): (any?, string?)
		if not self:_authorised(actor) then
			return nil, "NOT_AUTHORISED"
		end
		local anchor = if chair:IsA("BasePart")
			then chair
			else chair:FindFirstChildWhichIsA("BasePart")
		local actorRoot = root(actor)
		if
			not anchor
			or not actorRoot
			or (actorRoot.Position - anchor.Position).Magnitude
				> self.context.Configuration.Custody.MaximumBookingDistance
		then
			return nil, "TARGET_OUT_OF_RANGE"
		end
		local target = self:_chairOccupant(chair)
		if not target then
			return nil, "CHAIR_EMPTY"
		end
		if not self.cuffed[target.UserId] then
			return nil, "TARGET_NOT_CUFFED"
		end
		return self:_summary(target.UserId), nil
	end

	-- One ProximityPrompt per tagged chair, owned and connected here rather than
	-- per client - the same shape VendorService already uses for its stalls, so
	-- the prompt reaches touch, gamepad and keyboard alike with no bespoke input
	-- handling, and the trigger is validated exactly once, server-side, rather
	-- than trusted from a client request naming a chair by id.
	function CustodyService:_watchChair(model: Instance)
		if self.chairPrompts[model] then
			return
		end
		local anchor = if model:IsA("BasePart")
			then model
			else model:FindFirstChildWhichIsA("BasePart")
		if not anchor then
			self.context.Logger:Warning("Custody chair has no part to attach a prompt to", {
				Chair = model.Name,
			})
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RoleplayOSCustodyChairPrompt"
		prompt.ObjectText = "Custody Chair"
		prompt.ActionText = "Process Detainee"
		prompt.HoldDuration = 0.35
		prompt.MaxActivationDistance = self.context.Configuration.Custody.MaximumBookingDistance
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.ClickablePrompt = true
		prompt.Parent = anchor
		self.chairPrompts[model] = prompt
		self.chairPromptConnections[model] = prompt.Triggered:Connect(function(actor)
			local summary, reason = self:_processChair(actor, model)
			self.chairEvent:FireClient(
				actor,
				if summary
					then { Success = true, Data = summary }
					else { Success = false, Reason = reason }
			)
		end)
	end

	function CustodyService:_unwatchChair(model: Instance)
		local connection = self.chairPromptConnections[model]
		if connection then
			connection:Disconnect()
			self.chairPromptConnections[model] = nil
		end
		local prompt = self.chairPrompts[model]
		if prompt then
			prompt:Destroy()
			self.chairPrompts[model] = nil
		end
	end

	function CustodyService:Book(
		actor: Player,
		targetUserId: number,
		reason: string,
		offenceCodes: { string }?
	): (any?, string?)
		if not self:_authorised(actor) then
			return nil, "NOT_AUTHORISED"
		end
		if not self.cuffed[targetUserId] then
			return nil, "TARGET_NOT_CUFFED"
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		if
			not target
			or not self:_near(
				actor,
				target,
				self.context.Configuration.Custody.MaximumBookingDistance
			)
		then
			return nil, "TARGET_OUT_OF_RANGE"
		end
		if not self:_seatedInChair(target) then
			return nil, "TARGET_NOT_SEATED"
		end
		local filteredReason, filterReason =
			self:_filter(actor, reason, self.context.Configuration.Custody.MaximumReasonLength)
		if not filteredReason then
			return nil, filterReason
		end
		-- Text filtering yields, so all mutable authorisation and proximity checks are repeated.
		if
			not self:_authorised(actor)
			or not self.cuffed[targetUserId]
			or not self:_near(
				actor,
				target,
				self.context.Configuration.Custody.MaximumBookingDistance
			)
			or not self:_seatedInChair(target)
		then
			return nil, "TARGET_OUT_OF_RANGE"
		end
		if not self:_cellSpawn() then
			return nil, "CUSTODY_CELL_UNAVAILABLE"
		end
		local session = self.context.Services:Get("DataService"):GetSession(target)
		local character = session
			and session.ActiveCharacterId
			and session.Profile.Characters[session.ActiveCharacterId]
		if not character then
			return nil, "CHARACTER_UNAVAILABLE"
		end
		local selectedCodes = {}
		local seenCodes = {}
		for _, code in if type(offenceCodes) == "table" then offenceCodes else {} do
			if #selectedCodes >= self.context.Configuration.Custody.MaximumActiveOffences then
				break
			end
			if
				type(code) == "string"
				and self.context.Configuration.Custody.OffenceTariffs[code]
				and not seenCodes[code]
			then
				seenCodes[code] = true
				table.insert(selectedCodes, code)
			end
		end
		if #selectedCodes == 0 then
			table.insert(selectedCodes, "OTHER")
		end
		local sentence, sentenceReason =
			self:ApplySentence(target, selectedCodes, "CustodyBooking", actor.UserId)
		if not sentence then
			return nil, sentenceReason
		end
		character.CustodyRecord = character.CustodyRecord or { Bookings = {} }
		local record = {
			BookingId = HttpService:GenerateGUID(false),
			CharacterId = character.CharacterId,
			BookedAt = os.time(),
			Reason = filteredReason,
			BookingOfficerUserId = actor.UserId,
			Status = "InCustody",
			Cautioned = self.cuffed[targetUserId].CautionedAt ~= nil,
			Searched = self.cuffed[targetUserId].LastSearchAt ~= nil,
			OffenceCodes = selectedCodes,
			ReleaseAt = sentence.ReleaseAt,
		}
		table.insert(character.CustodyRecord.Bookings, record)
		trimToMaximum(
			character.CustodyRecord.Bookings,
			self.context.Configuration.Custody.MaximumBookingHistory
		)
		-- Backfilled here. CriminalRecord is written at character creation and never
		-- added by a migration, so a character made before it existed had none, and
		-- booking one raised after the sentence had already been applied: a live
		-- sentence, no booking record, and a detainee never moved to a cell.
		if type(character.CriminalRecord) ~= "table" then
			character.CriminalRecord = {}
		end
		table.insert(character.CriminalRecord, {
			Type = "CustodyBooking",
			RecordId = record.BookingId,
			CreatedAt = record.BookedAt,
			Reason = filteredReason,
			OffenceCodes = selectedCodes,
		})
		trimToMaximum(
			character.CriminalRecord,
			self.context.Configuration.Custody.MaximumCriminalRecordHistory
		)
		self.context.Services:Get("DataService"):MarkDirty(target)
		-- Person only, for the same reason a fine is: a booking changes the custody
		-- and criminal records and leaves the fleet exactly as it was.
		self.context.Services
			:Get("RecordIndexService")
			:ScheduleCharacter(target, character, "Person")
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = actor.UserId,
			Action = "Custody.Booked",
			Target = character.CharacterId,
			Metadata = { BookingId = record.BookingId },
		})
		self:_release(target)
		local spawned, spawnReason = self:SpawnInCell(target)
		if not spawned then
			self.context.Logger:Error("Booked detainee could not be moved to a custody cell", {
				UserId = target.UserId,
				Reason = spawnReason,
			})
		end
		return record, nil
	end
end
