--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local CustodyService = { cuffed = {}, connections = {}, commands = {}, running = false }

local function trimToMaximum(items: { any }, maximum: number)
	while #items > maximum do
		table.remove(items, 1)
	end
end

local function root(player: Player): BasePart?
	local item = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if item and item:IsA("BasePart") then item else nil
end

local function humanoid(player: Player): Humanoid?
	return if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
end

function CustodyService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("CustodyChanged")
end

function CustodyService:_sentence(player: Player): any?
	local session = self.context.Services:Get("DataService"):GetSession(player)
	return session and session.Profile.CustodySentence or nil
end

function CustodyService:GetSentence(player: Player): any
	local sentence = self:_sentence(player)
	local now = os.time()
	local releaseAt = if sentence then math.max(0, tonumber(sentence.ReleaseAt) or 0) else 0
	return {
		Active = releaseAt > now,
		ReleaseAt = releaseAt,
		RemainingSeconds = math.max(0, releaseAt - now),
		TotalSeconds = if sentence then math.max(0, tonumber(sentence.TotalSeconds) or 0) else 0,
		Offences = if sentence and type(sentence.Offences) == "table"
			then table.clone(sentence.Offences)
			else {},
		SimulationNotice = self.context.Configuration.Custody.SimulationNotice,
	}
end

function CustodyService:HasActiveSentence(player: Player): boolean
	return self:GetSentence(player).Active
end

function CustodyService:_policy(): { any }
	local policy = {}
	for code, tariff in self.context.Configuration.Custody.OffenceTariffs do
		if code ~= self.context.Configuration.Custody.DisconnectPenaltyCode then
			table.insert(policy, {
				Code = code,
				Name = tariff.Name,
				Seconds = tariff.Seconds,
			})
		end
	end
	table.sort(policy, function(a, b)
		return a.Name < b.Name
	end)
	return policy
end

function CustodyService:GetPolicy(): any
	return {
		Offences = self:_policy(),
		MaximumStackedSentenceSeconds = self.context.Configuration.Custody.MaximumStackedSentenceSeconds,
		SimulationNotice = self.context.Configuration.Custody.SimulationNotice,
	}
end

function CustodyService:ApplySentence(
	target: Player,
	offenceCodes: { string },
	source: string,
	actorUserId: number?
): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(target)
	if not session then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local config = self.context.Configuration.Custody
	local sentence = session.Profile.CustodySentence
	local now = os.time()
	local added = 0
	local accepted = {}
	local seen = {}
	for _, code in offenceCodes do
		local tariff = if type(code) == "string" then config.OffenceTariffs[code] else nil
		if tariff and not seen[code] and #accepted < config.MaximumActiveOffences then
			seen[code] = true
			added += tariff.Seconds
			table.insert(accepted, {
				Code = code,
				Name = tariff.Name,
				Seconds = tariff.Seconds,
				AppliedAt = now,
				Source = source,
				ActorUserId = actorUserId,
			})
		end
	end
	if added <= 0 then
		return nil, "NO_VALID_OFFENCES"
	end
	local remaining = math.max(0, (tonumber(sentence.ReleaseAt) or 0) - now)
	local finalDuration = math.min(config.MaximumStackedSentenceSeconds, remaining + added)
	sentence.ReleaseAt = now + finalDuration
	sentence.TotalSeconds = math.max(0, tonumber(sentence.TotalSeconds) or 0) + added
	sentence.UpdatedAt = now
	sentence.Offences = sentence.Offences or {}
	for _, offence in accepted do
		table.insert(sentence.Offences, offence)
	end
	trimToMaximum(sentence.Offences, config.MaximumActiveOffences)
	self.context.Services:Get("DataService"):MarkDirty(target)
	local summary = self:GetSentence(target)
	target:SetAttribute("RoleplayOSCustodyReleaseAt", summary.ReleaseAt)
	target:SetAttribute("RoleplayOSCustodyRemaining", summary.RemainingSeconds)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actorUserId or target.UserId,
		Action = "Custody.SentenceApplied",
		Target = tostring(target.UserId),
		Metadata = { Source = source, AddedSeconds = added, OffenceCount = #accepted },
	})
	return summary, nil
end

function CustodyService:_cellSpawn(): BasePart?
	for _, instance in CollectionService:GetTagged(self.context.Configuration.Custody.CellSpawnTag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			return instance
		end
		if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
			local part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
			if part then
				return part
			end
		end
	end
	return nil
end

function CustodyService:_placeInCell(player: Player): (boolean, string?)
	local cell = self:_cellSpawn()
	if not cell or not player.Character then
		return false, "CUSTODY_CELL_UNAVAILABLE"
	end
	player.Character:PivotTo(cell.CFrame * CFrame.new(0, 3, 0))
	return true, nil
end

function CustodyService:SpawnInCell(player: Player): (boolean, string?)
	if not self:HasActiveSentence(player) then
		return false, "NO_ACTIVE_CUSTODY_SENTENCE"
	end
	local cell = self:_cellSpawn()
	if not cell then
		return false, "CUSTODY_CELL_UNAVAILABLE"
	end
	local assigned, reason = self.context.Services:Get("RoleService"):Assign(player, "Civilian")
	if not assigned then
		return false, reason
	end
	player.RespawnLocation = if cell:IsA("SpawnLocation") then cell else nil
	local loaded, problem = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not loaded or not player.Character then
		self.context.Logger:Error("Custody cell spawn failed", {
			UserId = player.UserId,
			Error = tostring(problem),
		})
		return false, "CHARACTER_SPAWN_FAILED"
	end
	local placed, placeReason = self:_placeInCell(player)
	if not placed then
		return false, placeReason
	end
	local summary = self:GetSentence(player)
	player:SetAttribute("RoleplayOSCustodyReleaseAt", summary.ReleaseAt)
	player:SetAttribute("RoleplayOSCustodyRemaining", summary.RemainingSeconds)
	return true, nil
end

function CustodyService:_authorised(player: Player): boolean
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil and duty.DepartmentId == "Police"
end

function CustodyService:_lineOfSight(actor: Player, target: Player): boolean
	local actorRoot = root(actor)
	local targetRoot = root(target)
	if not actorRoot or not targetRoot then
		return false
	end
	local direction = targetRoot.Position - actorRoot.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { actor.Character, target.Character }
	return workspace:Raycast(actorRoot.Position, direction, params) == nil
end

function CustodyService:_near(actor: Player, target: Player, maximum: number): boolean
	local actorRoot = root(actor)
	local targetRoot = root(target)
	return actorRoot ~= nil
		and targetRoot ~= nil
		and (actorRoot.Position - targetRoot.Position).Magnitude <= maximum
		and self:_lineOfSight(actor, target)
end

function CustodyService:_filter(actor: Player, raw: any, maximum: number): (string?, string?)
	if type(raw) ~= "string" then
		return nil, "INVALID_GROUNDS"
	end
	local value = string.sub(string.gsub(raw, "[%c]", ""), 1, maximum)
	value = string.match(value, "^%s*(.-)%s*$") or ""
	if #value < 5 then
		return nil, "GROUNDS_REQUIRED"
	end
	if RunService:IsStudio() then
		return value, nil
	end
	local ok, filtered = pcall(function()
		return TextService:FilterStringAsync(value, actor.UserId)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" or #filtered < 5 then
		return nil, "TEXT_FILTER_UNAVAILABLE"
	end
	return filtered, nil
end

function CustodyService:_destroyEscort(state: any, target: Player?)
	for _, item in state.EscortInstances or {} do
		if item and item.Parent then
			item:Destroy()
		end
	end
	state.EscortInstances = nil
	state.EscortedByUserId = nil
	if target then
		local targetHumanoid = humanoid(target)
		if targetHumanoid then
			targetHumanoid.AutoRotate = true
			targetHumanoid.WalkSpeed = self.context.Configuration.Custody.CuffedWalkSpeed
		end
		local targetRoot = root(target)
		if targetRoot then
			pcall(targetRoot.SetNetworkOwner, targetRoot, nil)
		end
		target:SetAttribute("RoleplayOSEscorted", false)
	end
end

function CustodyService:_release(target: Player)
	local state = self.cuffed[target.UserId]
	if state then
		self:_destroyEscort(state, target)
	end
	self.cuffed[target.UserId] = nil
	target:SetAttribute("RoleplayOSCuffed", false)
	target:SetAttribute("RoleplayOSCuffPosition", nil)
	local targetHumanoid = humanoid(target)
	if targetHumanoid then
		targetHumanoid.WalkSpeed = self.context.Configuration.Needs.WalkSpeed
		targetHumanoid.JumpPower = 50
		targetHumanoid.AutoRotate = true
	end
end

function CustodyService:_summary(targetUserId: number): any
	local state = self.cuffed[targetUserId]
	return {
		TargetUserId = targetUserId,
		Cuffed = state ~= nil,
		CuffPosition = state and state.CuffPosition or nil,
		OfficerUserId = state and state.OfficerUserId or nil,
		Escorted = state and state.EscortedByUserId ~= nil or false,
		EscortedByUserId = state and state.EscortedByUserId or nil,
		Cautioned = state and state.CautionedAt ~= nil or false,
		Searched = state and state.LastSearchAt ~= nil or false,
	}
end

function CustodyService:SetCuffed(
	actor: Player,
	targetUserId: number,
	mode: string?
): (any?, string?)
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
	local targetHumanoid = humanoid(target)
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return nil, "TARGET_UNAVAILABLE"
	end
	local existing = self.cuffed[targetUserId]
	local requestedMode = mode or "Apply"
	if requestedMode ~= "Apply" and requestedMode ~= "Remove" then
		return nil, "INVALID_CUFF_MODE"
	end
	if requestedMode == "Remove" and existing then
		self:_release(target)
	elseif requestedMode == "Apply" and not existing then
		self.cuffed[targetUserId] = {
			OfficerUserId = actor.UserId,
			CuffedAt = os.time(),
			CuffPosition = "Rear",
		}
		target:SetAttribute("RoleplayOSCuffed", true)
		target:SetAttribute("RoleplayOSCuffPosition", "Rear")
		targetHumanoid.WalkSpeed = self.context.Configuration.Custody.CuffedWalkSpeed
		targetHumanoid.JumpPower = 0
	end
	local summary = self:_summary(targetUserId)
	self.event:FireClient(target, { Kind = "State", State = summary })
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = if summary.Cuffed then "Custody.Cuffed" else "Custody.Released",
		Target = tostring(targetUserId),
		Metadata = { Position = summary.CuffPosition },
	})
	return summary, nil
end

function CustodyService:_escort(actor: Player, target: Player, state: any): (any?, string?)
	if state.EscortedByUserId then
		if state.EscortedByUserId ~= actor.UserId then
			return nil, "ALREADY_ESCORTED"
		end
		self:_destroyEscort(state, target)
		return self:_summary(target.UserId), nil
	end
	for _, otherState in self.cuffed do
		if otherState.EscortedByUserId == actor.UserId then
			return nil, "OFFICER_ALREADY_ESCORTING"
		end
	end
	local actorRoot = root(actor)
	local targetRoot = root(target)
	local targetHumanoid = humanoid(target)
	if not actorRoot or not targetRoot or not targetHumanoid then
		return nil, "TARGET_UNAVAILABLE"
	end
	local officerAttachment = Instance.new("Attachment")
	officerAttachment.Name = "RoleplayOSEscortPoint"
	officerAttachment.Position =
		Vector3.new(0, 0, self.context.Configuration.Custody.EscortDistance)
	officerAttachment.Parent = actorRoot
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "RoleplayOSEscortTarget"
	targetAttachment.Parent = targetRoot
	local position = Instance.new("AlignPosition")
	position.Name = "RoleplayOSEscortPosition"
	position.Attachment0 = targetAttachment
	position.Attachment1 = officerAttachment
	position.ApplyAtCenterOfMass = true
	position.MaxForce = self.context.Configuration.Custody.EscortMaximumForce
	position.MaxVelocity = self.context.Configuration.Custody.EscortMaximumVelocity
	position.Responsiveness = 18
	position.ReactionForceEnabled = false
	position.Parent = targetRoot
	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "RoleplayOSEscortOrientation"
	orientation.Attachment0 = targetAttachment
	orientation.Attachment1 = officerAttachment
	orientation.MaxTorque = self.context.Configuration.Custody.EscortMaximumForce
	orientation.Responsiveness = 16
	orientation.ReactionTorqueEnabled = false
	orientation.Parent = targetRoot
	state.EscortedByUserId = actor.UserId
	state.EscortInstances = { officerAttachment, targetAttachment, position, orientation }
	targetHumanoid.WalkSpeed = 0
	targetHumanoid.AutoRotate = false
	target:SetAttribute("RoleplayOSEscorted", true)
	pcall(targetRoot.SetNetworkOwner, targetRoot, nil)
	return self:_summary(target.UserId), nil
end

function CustodyService:_search(
	actor: Player,
	target: Player,
	state: any,
	data: any
): (any?, string?)
	local grounds, reason = self:_filter(
		actor,
		data.Grounds,
		self.context.Configuration.Custody.MaximumSearchGroundsLength
	)
	if not grounds then
		return nil, reason
	end
	-- Filtering yields. Revalidate the security boundary before recording a search.
	if
		not self:_authorised(actor)
		or not self.cuffed[target.UserId]
		or not self:_near(
			actor,
			target,
			self.context.Configuration.Custody.MaximumInteractionDistance
		)
	then
		return nil, "TARGET_OUT_OF_RANGE"
	end
	local power = data.Power
	if
		type(power) ~= "string"
		or not table.find(self.context.Configuration.Custody.SearchPowers, power)
	then
		return nil, "INVALID_SEARCH_POWER"
	end
	local items = {}
	local seen = {}
	for _, container in { target:FindFirstChildOfClass("Backpack"), target.Character } do
		for _, item in if container then container:GetChildren() else {} do
			if item:IsA("Tool") and not seen[item.Name] then
				seen[item.Name] = true
				table.insert(items, item.Name)
				if #items >= self.context.Configuration.Custody.MaximumSearchItems then
					break
				end
			end
		end
	end
	table.sort(items)
	state.LastSearchAt = os.time()
	state.LastSearchByUserId = actor.UserId
	self.event:FireClient(target, {
		Kind = "SearchNotice",
		OfficerUserId = actor.UserId,
		Grounds = grounds,
		Power = power,
	})
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Custody.Searched",
		Target = tostring(target.UserId),
		Metadata = { Power = power, ItemCount = #items },
	})
	return {
		State = self:_summary(target.UserId),
		Items = items,
		Grounds = grounds,
		Power = power,
		RecordEntitlement = true,
	},
		nil
end

function CustodyService:_vehicle(actor: Player, target: Player, state: any): (any?, string?)
	local targetHumanoid = humanoid(target)
	if not targetHumanoid then
		return nil, "TARGET_UNAVAILABLE"
	end
	if targetHumanoid.SeatPart then
		targetHumanoid.Sit = false
		local actorRoot = root(actor)
		local targetRoot = root(target)
		if actorRoot and targetRoot then
			targetRoot.CFrame = actorRoot.CFrame * CFrame.new(2.5, 0, 0)
		end
		state.VehicleSeat = nil
		return self:_summary(target.UserId), nil
	end
	local actorRoot = root(actor)
	local targetRoot = root(target)
	if not actorRoot or not targetRoot then
		return nil, "TARGET_UNAVAILABLE"
	end
	local nearest: Seat? = nil
	local nearestDistance = math.huge
	for _, candidate in
		CollectionService:GetTagged(self.context.Configuration.Custody.VehicleSeatTag)
	do
		if
			candidate:IsA("Seat")
			and candidate:IsDescendantOf(workspace)
			and not candidate.Occupant
		then
			local officerDistance = (candidate.Position - actorRoot.Position).Magnitude
			local targetDistance = (candidate.Position - targetRoot.Position).Magnitude
			local distance = math.max(officerDistance, targetDistance)
			if
				distance <= self.context.Configuration.Custody.MaximumVehicleDistance
				and distance < nearestDistance
			then
				nearest = candidate
				nearestDistance = distance
			end
		end
	end
	if not nearest then
		return nil, "CUSTODY_SEAT_UNAVAILABLE"
	end
	self:_destroyEscort(state, target)
	nearest:Sit(targetHumanoid)
	state.VehicleSeat = nearest
	return self:_summary(target.UserId), nil
end

function CustodyService:Action(
	actor: Player,
	targetUserId: number,
	action: string,
	data: any
): (any?, string?)
	if not self:_authorised(actor) or actor.UserId == targetUserId then
		return nil, "NOT_AUTHORISED"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local state = self.cuffed[targetUserId]
	if not target or not state then
		return nil, "TARGET_NOT_CUFFED"
	end
	if
		not self:_near(actor, target, self.context.Configuration.Custody.MaximumInteractionDistance)
	then
		return nil, "TARGET_OUT_OF_RANGE"
	end
	local result, reason
	if action == "Status" then
		result = self:_summary(targetUserId)
	elseif action == "Escort" then
		result, reason = self:_escort(actor, target, state)
	elseif action == "Search" then
		result, reason = self:_search(actor, target, state, data)
	elseif action == "Vehicle" then
		result, reason = self:_vehicle(actor, target, state)
	elseif action == "Caution" then
		state.CautionedAt = os.time()
		state.CautionedByUserId = actor.UserId
		local caution = self.context.Configuration.Custody.ArrestCaution
		self.event:FireClient(target, {
			Kind = "Caution",
			Text = caution,
			OfficerUserId = actor.UserId,
			SimulationNotice = self.context.Configuration.Custody.SimulationNotice,
		})
		result = { State = self:_summary(targetUserId), Caution = caution }
	elseif action == "CuffPosition" then
		local position = data.Position
		if position ~= "Front" and position ~= "Rear" then
			return nil, "INVALID_CUFF_POSITION"
		end
		state.CuffPosition = position
		target:SetAttribute("RoleplayOSCuffPosition", position)
		result = self:_summary(targetUserId)
	elseif action == "Release" then
		if state.OfficerUserId ~= actor.UserId then
			return nil, "NOT_MANAGING_OFFICER"
		end
		self:_release(target)
		result = self:_summary(targetUserId)
	else
		return nil, "INVALID_CUSTODY_ACTION"
	end
	if not result then
		return nil, reason
	end
	if action ~= "Status" and action ~= "Search" then
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = actor.UserId,
			Action = "Custody." .. action,
			Target = tostring(targetUserId),
			Metadata = {},
		})
	end
	return result, nil
end

function CustodyService:_nearestManaged(actor: Player): Player?
	local actorRoot = root(actor)
	if not actorRoot then
		return nil
	end
	local nearest
	local distance = self.context.Configuration.Custody.MaximumInteractionDistance
	for userId, state in self.cuffed do
		if state.OfficerUserId == actor.UserId or state.EscortedByUserId == actor.UserId then
			local target = Players:GetPlayerByUserId(userId)
			local targetRoot = target and root(target)
			if target and targetRoot then
				local current = (targetRoot.Position - actorRoot.Position).Magnitude
				if current <= distance then
					nearest = target
					distance = current
				end
			end
		end
	end
	return nearest
end

function CustodyService:_command(
	alias: string,
	secondary: string?,
	callback: (Player, string) -> ()
)
	local command = Instance.new("TextChatCommand")
	command.Name = "RoleplayOS" .. string.gsub(alias, "^/", "")
	command.PrimaryAlias = alias
	command.SecondaryAlias = secondary or ""
	command.AutocompleteVisible = true
	command.Parent = TextChatService
	table.insert(self.commands, command)
	table.insert(
		self.connections,
		command.Triggered:Connect(function(source, message)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				callback(player, message)
			end
		end)
	)
end

function CustodyService:Start()
	self.running = true
	local function watch(player: Player)
		table.insert(
			self.connections,
			player.CharacterAdded:Connect(function()
				task.defer(function()
					if self:HasActiveSentence(player) then
						self:_placeInCell(player)
						return
					end
					local state = self.cuffed[player.UserId]
					if state then
						player:SetAttribute("RoleplayOSCuffed", true)
						player:SetAttribute("RoleplayOSCuffPosition", state.CuffPosition)
						local targetHumanoid = humanoid(player)
						if targetHumanoid then
							targetHumanoid.WalkSpeed =
								self.context.Configuration.Custody.CuffedWalkSpeed
							targetHumanoid.JumpPower = 0
						end
					end
				end)
			end)
		)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			if self.cuffed[player.UserId] then
				self:ApplySentence(
					player,
					{ self.context.Configuration.Custody.DisconnectPenaltyCode },
					"DisconnectWhileRestrained",
					nil
				)
			end
			self.cuffed[player.UserId] = nil
			local releaseUserIds = {}
			for userId, state in self.cuffed do
				if
					state.OfficerUserId == player.UserId
					or state.EscortedByUserId == player.UserId
				then
					table.insert(releaseUserIds, userId)
				end
			end
			for _, userId in releaseUserIds do
				local target = Players:GetPlayerByUserId(userId)
				if target then
					self:_release(target)
				end
			end
		end)
	)
	task.spawn(function()
		while self.running do
			task.wait(1)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local sentence = self:_sentence(player)
				if sentence then
					local releaseAt = math.max(0, tonumber(sentence.ReleaseAt) or 0)
					if releaseAt > now then
						player:SetAttribute("RoleplayOSCustodyReleaseAt", releaseAt)
						player:SetAttribute("RoleplayOSCustodyRemaining", releaseAt - now)
					elseif releaseAt > 0 then
						sentence.ReleaseAt = 0
						sentence.UpdatedAt = now
						player:SetAttribute("RoleplayOSCustodyReleaseAt", nil)
						player:SetAttribute("RoleplayOSCustodyRemaining", 0)
						player.RespawnLocation = nil
						self.context.Services:Get("DataService"):MarkDirty(player)
						self.context.Services:Get("AuditService"):Record({
							ActorUserId = player.UserId,
							Action = "Custody.SentenceCompleted",
							Target = tostring(player.UserId),
							Metadata = {},
						})
						pcall(function()
							player:LoadCharacterAsync()
						end)
					end
				end
			end
		end
	end)
	self:_command("/caution", nil, function(actor)
		local target = self:_nearestManaged(actor)
		if target then
			self:Action(actor, target.UserId, "Caution", {})
		end
	end)
	self:_command("/search", "/gowisely", function(actor, message)
		local target = self:_nearestManaged(actor)
		local grounds = string.match(message, "^%S+%s+(.+)$")
		if target and grounds then
			self:Action(actor, target.UserId, "Search", {
				Grounds = grounds,
				Power = self.context.Configuration.Custody.SearchPowers[1],
			})
		end
	end)
end

function CustodyService:_atDesk(player: Player): boolean
	local playerRoot = root(player)
	if not playerRoot then
		return false
	end
	for _, desk in CollectionService:GetTagged(self.context.Configuration.Custody.BookingDeskTag) do
		if
			desk:IsA("BasePart")
			and (playerRoot.Position - desk.Position).Magnitude
				<= self.context.Configuration.Custody.MaximumBookingDistance
		then
			return true
		end
	end
	return false
end

function CustodyService:Book(
	actor: Player,
	targetUserId: number,
	reason: string,
	offenceCodes: { string }?
): (any?, string?)
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
	local filteredReason, filterReason =
		self:_filter(actor, reason, self.context.Configuration.Custody.MaximumReasonLength)
	if not filteredReason then
		return nil, filterReason
	end
	-- Text filtering yields, so all mutable authorisation and proximity checks are repeated.
	if
		not self:_authorised(actor)
		or not self:_atDesk(actor)
		or not self.cuffed[targetUserId]
		or not self:_near(actor, target, self.context.Configuration.Custody.MaximumBookingDistance)
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
	self.context.Services:Get("RecordIndexService"):ScheduleCharacter(target, character)
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

function CustodyService:Destroy()
	self.running = false
	for userId in self.cuffed do
		local target = Players:GetPlayerByUserId(userId)
		if target then
			self:_release(target)
		end
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, command in self.commands do
		command:Destroy()
	end
	table.clear(self.connections)
	table.clear(self.commands)
	table.clear(self.cuffed)
end

return CustodyService
