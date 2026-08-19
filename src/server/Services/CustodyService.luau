--!strict

local RolePermissions =
	require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.RolePermissions)

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

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
	self.chairEvent = context.Network:RegisterEvent("CustodyChairProcessed")
	self.chairPrompts = {}
	self.chairPromptConnections = {}
end

function CustodyService:_sentence(player: Player): any?
	local session = self.context.Services:Get("DataService"):GetSession(player)
	return session and session.Profile.CustodySentence or nil
end

function CustodyService:GetSentence(player: Player): any
	local sentence = self:_sentence(player)
	local remaining = if sentence
		then math.max(0, math.floor(tonumber(sentence.RemainingSeconds) or 0))
		else 0
	return {
		Active = remaining > 0,
		-- A display estimate only. RemainingSeconds is the persisted authority so
		-- offline time never serves a sentence.
		ReleaseAt = if remaining > 0 then os.time() + remaining else 0,
		RemainingSeconds = remaining,
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
				-- Optional, because the catch-all and the disconnect penalty are not
				-- offences under anything.
				Statute = tariff.Statute,
				Seconds = tariff.Seconds,
			})
		end
	end
	table.sort(policy, function(a, b)
		return a.Name < b.Name
	end)
	return policy
end

function CustodyService:GetPolicy(player: Player?): any
	local mode = self.context.Services:Get("ServerModeService"):Kind()
	local earlyRelease = self.context.Configuration.Custody.PublicEarlyRelease
	local configuredProducts = {}
	for _, product in earlyRelease.Products do
		if type(product.ProductId) == "number" and product.ProductId > 0 then
			table.insert(configuredProducts, table.clone(product))
		end
	end
	local session = player and self.context.Services:Get("DataService"):GetSession(player)
	local credits = if session and session.Profile.Consumables
		then math.max(0, math.floor(tonumber(session.Profile.Consumables.EarlyReleaseCredits) or 0))
		else 0
	return {
		Offences = self:_policy(),
		MaximumStackedSentenceSeconds = self.context.Configuration.Custody.MaximumStackedSentenceSeconds,
		SimulationNotice = self.context.Configuration.Custody.SimulationNotice,
		ServerKind = mode,
		-- Always true now: sitting a cuffed detainee in a tagged chair, not
		-- standing near a desk, and not limited to Whitelisted servers any more.
		BookingChairRequired = true,
		EarlyReleaseCredits = if mode == "Public" then credits else 0,
		EarlyReleaseProducts = if mode == "Public" then configuredProducts else {},
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
	local remaining = math.max(0, tonumber(sentence.RemainingSeconds) or 0)
	local finalDuration = math.min(config.MaximumStackedSentenceSeconds, remaining + added)
	sentence.RemainingSeconds = finalDuration
	sentence.ReleaseAt = 0
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

function CustodyService:AddDisconnectPenalty(player: Player): boolean
	local sentence = self:_sentence(player)
	local remaining = sentence and math.max(0, tonumber(sentence.RemainingSeconds) or 0) or 0
	if remaining <= 0 then
		return false
	end
	local config = self.context.Configuration.Custody
	local added = math.max(0, tonumber(config.DisconnectPenaltySeconds) or 30)
	sentence.RemainingSeconds = math.min(config.MaximumStackedSentenceSeconds, remaining + added)
	sentence.ReleaseAt = 0
	sentence.UpdatedAt = os.time()
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Custody.DisconnectPenalty",
		Target = tostring(player.UserId),
		Metadata = { AddedSeconds = added },
	})
	return true
end

function CustodyService:UseEarlyReleaseCredit(player: Player, sourceId: string?): (boolean, string?)
	if self.context.Services:Get("ServerModeService"):Kind() ~= "Public" then
		return false, "PUBLIC_SERVER_REQUIRED"
	end
	local dataService = self.context.Services:Get("DataService")
	local session = dataService:GetSession(player)
	if not session then
		return false, "NO_SESSION"
	end
	if not self:HasActiveSentence(player) then
		return false, "NO_ACTIVE_CUSTODY_SENTENCE"
	end
	local consumables = session.Profile.Consumables
	local credits = math.max(0, math.floor(tonumber(consumables.EarlyReleaseCredits) or 0))
	if credits <= 0 then
		return false, "NO_EARLY_RELEASE_CREDITS"
	end
	consumables.EarlyReleaseCredits = credits - 1
	local released, reason = self:_completeSentence(player, "EarlyReleaseCredit", sourceId)
	if not released then
		consumables.EarlyReleaseCredits = credits
		dataService:MarkDirty(player)
		return false, reason
	end
	dataService:MarkDirty(player)
	self.event:FireClient(player, { Kind = "EarlyRelease", Credits = credits - 1 })
	return true, nil
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

-- Custody is a power the role holds, not a department it belongs to.
--
-- This was `duty.DepartmentId == "Police"`, and PCSO is a Police role that is
-- free on the public tier, so search, escort, caution and booking somebody into
-- a half hour sentence were available to every player in the game.
function CustodyService:_authorised(player: Player): boolean
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil and RolePermissions.has(self.context.Configuration, duty, "Custody")
end

function CustodyService:IsAuthorisedForSeizure(player: Player): boolean
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil
		and RolePermissions.has(self.context.Configuration, duty, "Custody")
		and duty.DepartmentId == "Police"
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
	local filtered, reason = TextFilter.forBroadcast(value, actor.UserId)
	if not filtered or #filtered < 5 then
		return nil, reason or "TEXT_FILTER_UNAVAILABLE"
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
		targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
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
	local equipped = false
	if actor.Character then
		for _, child in actor.Character:GetChildren() do
			if
				child:IsA("Tool")
				and (
					child.Name == "Handcuffs"
					or child:GetAttribute("RoleplayOSToolId") == "Handcuffs"
				)
			then
				equipped = true
				break
			end
		end
	end
	if not equipped then
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
		local newState = {
			OfficerUserId = actor.UserId,
			CuffedAt = os.time(),
			CuffPosition = "Rear",
		}
		self.cuffed[targetUserId] = newState
		target:SetAttribute("RoleplayOSCuffed", true)
		target:SetAttribute("RoleplayOSCuffPosition", "Rear")
		targetHumanoid.WalkSpeed = self.context.Configuration.Custody.CuffedWalkSpeed
		targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		-- Applying rear cuffs immediately establishes the physical escort pose:
		-- detainee in front, officer behind and facing the back of their head.
		-- The escort constraints remain server-owned and are removed by every
		-- existing release/death/reset/disconnect path.
		self:_escort(actor, target, newState)
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
	-- Roblox characters face local -Z. Placing the detainee on that side keeps
	-- the officer behind them, looking toward the back of their head, while both
	-- bodies share the same forward orientation.
	officerAttachment.Position =
		Vector3.new(0, 0, -self.context.Configuration.Custody.EscortDistance)
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
	elseif action == "SeizeWeapons" then
		result, reason = self.context.Services:Get("MeleeWeaponService"):Seize(actor, targetUserId)
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
	local chairTag = self.context.Configuration.Custody.ChairTag
	for _, model in CollectionService:GetTagged(chairTag) do
		self:_watchChair(model)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(chairTag):Connect(function(model)
			self:_watchChair(model)
		end)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(chairTag):Connect(function(model)
			self:_unwatchChair(model)
		end)
	)
	local function restoreSentence(player: Player)
		task.spawn(function()
			local deadline = os.clock() + 20
			while
				player.Parent
				and not self.context.Services:Get("DataService"):GetSession(player)
				and os.clock() < deadline
			do
				task.wait(0.1)
			end
			if player.Parent and self:HasActiveSentence(player) then
				local summary = self:GetSentence(player)
				player:SetAttribute("RoleplayOSCustodyReleaseAt", summary.ReleaseAt)
				player:SetAttribute("RoleplayOSCustodyRemaining", summary.RemainingSeconds)
				self:SpawnInCell(player)
			end
		end)
	end
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
							targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
						end
					end
				end)
			end)
		)
		restoreSentence(player)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			-- Only an already processed sentence is penalised. Merely being cuffed
			-- is not an arrest and must never create a sentence by itself.
			self:AddDisconnectPenalty(player)
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
				-- Guarded per prisoner. This loop is the only thing that ends a
				-- sentence, so a throw for one detainee left every detainee in the
				-- server serving theirs for ever, with the server restarting as the
				-- only way out.
				local released, problem = pcall(function()
					local sentence = self:_sentence(player)
					if sentence then
						local remaining = math.max(0, tonumber(sentence.RemainingSeconds) or 0)
						if remaining > 0 then
							remaining = math.max(0, remaining - 1)
							sentence.RemainingSeconds = remaining
							sentence.ReleaseAt = 0
							sentence.UpdatedAt = now
							player:SetAttribute("RoleplayOSCustodyReleaseAt", now + remaining)
							player:SetAttribute("RoleplayOSCustodyRemaining", remaining)
							if remaining == 0 then
								local completed, completeReason =
									self:_completeSentence(player, "Served", nil)
								if not completed then
									-- Retried rather than left at a permanently zeroed
									-- timer. _completeSentence can fail for reasons that
									-- resolve themselves a few seconds later -- no
									-- civilian spawn configured yet, a transient role or
									-- spawn failure -- and the alternative is a prisoner
									-- stuck in custody forever with a clock reading zero,
									-- since the `remaining > 0` gate above never lets this
									-- branch run again once it is.
									local retrySeconds = 5
									sentence.RemainingSeconds = retrySeconds
									sentence.ReleaseAt = 0
									sentence.UpdatedAt = now
									player:SetAttribute(
										"RoleplayOSCustodyReleaseAt",
										now + retrySeconds
									)
									player:SetAttribute("RoleplayOSCustodyRemaining", retrySeconds)
									self.context.Logger:Warning(
										"Custody release on time served failed, retrying",
										{ UserId = player.UserId, Reason = completeReason }
									)
								end
							elseif remaining % 10 == 0 then
								self.context.Services:Get("DataService"):MarkDirty(player)
							end
						end
					end
				end)
				if not released then
					self.context.Logger:Error("Custody sentence tick failed", {
						UserId = player.UserId,
						Error = tostring(problem),
					})
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

function CustodyService:_completeSentence(
	player: Player,
	source: string,
	receiptId: string?
): (boolean, string?)
	local civilianSpawnId = nil
	local civilianStationId = nil
	for spawnId, definition in self.context.Configuration.Spawns do
		if definition.TeamName == "Civilian" then
			civilianSpawnId = spawnId
			civilianStationId = definition.StationId
			break
		end
	end
	if not civilianSpawnId or not civilianStationId then
		return false, "CIVILIAN_SPAWN_NOT_CONFIGURED"
	end
	if not player.Parent then
		return false, "PLAYER_LEFT"
	end
	local previousTeam = player.Team
	local previousRespawnLocation = player.RespawnLocation
	local assigned, assignReason =
		self.context.Services:Get("RoleService"):Assign(player, "Civilian")
	if not assigned then
		return false, assignReason or "CIVILIAN_ROLE_ASSIGNMENT_FAILED"
	end
	if not player.Parent then
		player.Team = previousTeam
		return false, "PLAYER_LEFT"
	end
	local spawned, spawnReason = self.context.Services:Get("SpawnService"):Spawn(player, {
		RoleId = "Civilian",
		StationId = civilianStationId,
		SpawnId = civilianSpawnId,
	})
	if not spawned then
		player.Team = previousTeam
		player.RespawnLocation = previousRespawnLocation
		return false, spawnReason or "CIVILIAN_SPAWN_FAILED"
	end
	if not player.Parent then
		return false, "PLAYER_LEFT"
	end
	local sentence = self:_sentence(player)
	if sentence then
		sentence.RemainingSeconds = 0
		sentence.ReleaseAt = 0
		sentence.UpdatedAt = os.time()
	end
	player:SetAttribute("RoleplayOSCustodyReleaseAt", nil)
	player:SetAttribute("RoleplayOSCustodyRemaining", 0)
	player.RespawnLocation = nil
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Custody.SentenceCompleted",
		Target = tostring(player.UserId),
		Metadata = { Source = source, ReceiptId = receiptId },
	})
	return true, nil
end

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
	local anchor = if chair:IsA("BasePart") then chair else chair:FindFirstChildWhichIsA("BasePart")
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
	local anchor = if model:IsA("BasePart") then model else model:FindFirstChildWhichIsA("BasePart")
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
		or not self:_near(actor, target, self.context.Configuration.Custody.MaximumBookingDistance)
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
		or not self:_near(actor, target, self.context.Configuration.Custody.MaximumBookingDistance)
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
	self.context.Services:Get("RecordIndexService"):ScheduleCharacter(target, character, "Person")
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
	for model in self.chairPrompts do
		self:_unwatchChair(model)
	end
	table.clear(self.chairPrompts)
	table.clear(self.chairPromptConnections)
end

return CustodyService
