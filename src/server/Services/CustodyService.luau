--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local CustodyService = { cuffed = {}, connections = {} }

function CustodyService:Init(context: any)
	self.context = context
end
function CustodyService:_release(player: Player)
	self.cuffed[player.UserId] = nil
	player:SetAttribute("RoleplayOSCuffed", false)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = self.context.Configuration.Needs.WalkSpeed
		humanoid.JumpPower = 50
	end
end

function CustodyService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.cuffed[player.UserId] = nil
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			table.insert(
				self.connections,
				player.CharacterAdded:Connect(function()
					self:_release(player)
				end)
			)
		end)
	)
	for _, player in Players:GetPlayers() do
		table.insert(
			self.connections,
			player.CharacterAdded:Connect(function()
				self:_release(player)
			end)
		)
	end
end

function CustodyService:_authorised(player: Player): boolean
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil and duty.DepartmentId == "Police"
end

function CustodyService:_near(a: Player, b: Player, maximum: number): boolean
	local ar = a.Character and a.Character:FindFirstChild("HumanoidRootPart")
	local br = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
	return ar ~= nil and br ~= nil and (ar.Position - br.Position).Magnitude <= maximum
end

function CustodyService:Toggle(actor: Player, targetUserId: number): (any?, string?)
	if not self:_authorised(actor) or actor.UserId == targetUserId then
		return nil, "NOT_AUTHORISED"
	end
	local equipped = actor.Character and actor.Character:FindFirstChild("Handcuffs")
	if not equipped or not equipped:IsA("Tool") then
		return nil, "HANDCUFFS_MUST_BE_EQUIPPED"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if
		not target
		or not self:_near(
			actor,
			target,
			self.context.Configuration.Custody.MaximumInteractionDistance
		)
	then
		return nil, "TARGET_OUT_OF_RANGE"
	end
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, "TARGET_UNAVAILABLE"
	end
	local enabled = not self.cuffed[targetUserId]
	self.cuffed[targetUserId] = enabled or nil
	target:SetAttribute("RoleplayOSCuffed", enabled)
	humanoid.WalkSpeed = if enabled then 7 else self.context.Configuration.Needs.WalkSpeed
	humanoid.JumpPower = if enabled then 0 else 50
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = if enabled then "Custody.Cuffed" else "Custody.Released",
		Target = tostring(targetUserId),
		Metadata = {},
	})
	return { Cuffed = enabled, TargetUserId = targetUserId }, nil
end

function CustodyService:_atDesk(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, desk in CollectionService:GetTagged(self.context.Configuration.Custody.BookingDeskTag) do
		if
			desk:IsA("BasePart")
			and (root.Position - desk.Position).Magnitude
				<= self.context.Configuration.Custody.MaximumBookingDistance
		then
			return true
		end
	end
	return false
end

function CustodyService:Book(actor: Player, targetUserId: number, reason: string): (any?, string?)
	if not self:_authorised(actor) or not self:_atDesk(actor) then
		return nil, "BOOKING_DESK_REQUIRED"
	end
	if not self.cuffed[targetUserId] then
		return nil, "TARGET_NOT_CUFFED"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if
		not target
		or not self:_near(actor, target, self.context.Configuration.Custody.MaximumBookingDistance)
	then
		return nil, "TARGET_OUT_OF_RANGE"
	end
	reason = string.gsub(
		string.sub(reason, 1, self.context.Configuration.Custody.MaximumReasonLength),
		"[%c]",
		""
	)
	if #reason < 3 then
		return nil, "INVALID_REASON"
	end
	local filteredOk, filteredReason = pcall(function()
		return TextService:FilterStringAsync(reason, actor.UserId)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not filteredOk or type(filteredReason) ~= "string" or #filteredReason < 3 then
		return nil, "TEXT_FILTER_UNAVAILABLE"
	end
	reason = filteredReason
	local session = self.context.Services:Get("DataService"):GetSession(target)
	local character = session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
	if not character then
		return nil, "CHARACTER_UNAVAILABLE"
	end
	character.CustodyRecord = character.CustodyRecord or { Bookings = {} }
	local record = {
		BookingId = HttpService:GenerateGUID(false),
		CharacterId = character.CharacterId,
		BookedAt = os.time(),
		Reason = reason,
		BookingOfficerUserId = actor.UserId,
		Status = "InCustody",
	}
	table.insert(character.CustodyRecord.Bookings, record)
	table.insert(character.CriminalRecord, {
		Type = "CustodyBooking",
		RecordId = record.BookingId,
		CreatedAt = record.BookedAt,
		Reason = reason,
	})
	self.context.Services:Get("DataService"):MarkDirty(target)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Custody.Booked",
		Target = character.CharacterId,
		Metadata = { BookingId = record.BookingId },
	})
	return record, nil
end

function CustodyService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.cuffed)
end
return CustodyService
