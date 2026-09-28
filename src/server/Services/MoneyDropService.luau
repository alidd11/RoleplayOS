--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyDropPolicy = require(ReplicatedStorage.RoleplayOS.Shared.MoneyDropPolicy)

local MoneyDropService = {
	drops = {},
	connections = {},
	running = false,
	dropping = {},
	pendingDrops = 0,
}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function recoveryRecord(dropId: string, record: any): any
	return {
		DropId = dropId,
		OwnerUserId = record.OwnerUserId,
		OwnerCharacterId = record.OwnerCharacterId,
		Amount = record.Amount,
		CreatedAt = record.CreatedAt or os.time(),
	}
end

function MoneyDropService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.MoneyDrops
	table.clear(self.connections)
	table.clear(self.dropping)
	self.pendingDrops = 0
	self.running = false
end

function MoneyDropService:_claimDropSlot(player: Player): (any?, string?)
	local userId = player.UserId
	if self.dropping[userId] then
		return nil, "MONEY_DROP_IN_PROGRESS"
	end

	local owned = 0
	local activeCount = 0
	for _, record in self.drops do
		activeCount += 1
		if record.OwnerUserId == userId then
			owned += 1
		end
	end
	if owned >= self.settings.MaximumActivePerPlayer then
		return nil, "TOO_MANY_ACTIVE_DROPS"
	end
	if activeCount + self.pendingDrops >= self.settings.MaximumActiveGlobal then
		return nil, "SERVER_DROP_LIMIT"
	end

	-- No yield occurs between checking the live counts and reserving this slot,
	-- so concurrent requests cannot all observe the same spare capacity.
	local claim = {}
	self.dropping[userId] = claim
	self.pendingDrops += 1
	return claim, nil
end

function MoneyDropService:_releaseDropSlot(userId: number, claim: any)
	if self.dropping[userId] ~= claim then
		return
	end
	self.dropping[userId] = nil
	self.pendingDrops = math.max(0, self.pendingDrops - 1)
end

function MoneyDropService:_activeCharacter(player: Player): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local characterId = session and session.ActiveCharacterId
	local character = characterId and session.Profile.Characters[characterId]
	if not character then
		return nil, nil
	end
	return character, characterId
end

function MoneyDropService:_rootPosition(player: Player): Vector3?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

function MoneyDropService:_dropPosition(player: Player): Vector3?
	local rootPosition = self:_rootPosition(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPosition or not root or not root:IsA("BasePart") then
		return nil
	end
	return rootPosition + root.CFrame.LookVector * self.settings.DropAheadStuds
end

function MoneyDropService:_remove(dropId: string, reason: string?)
	local record = self.drops[dropId]
	if not record then
		return
	end
	self.drops[dropId] = nil
	if record.Connection then
		record.Connection:Disconnect()
	end
	if record.ExpiryThread then
		task.cancel(record.ExpiryThread)
		record.ExpiryThread = nil
	end
	if record.Part then
		record.Part:Destroy()
	end
	if reason then
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = record.OwnerUserId,
			CharacterId = record.OwnerCharacterId,
			Action = "MoneyDrop." .. reason,
			Target = dropId,
			Metadata = { Amount = record.Amount },
		})
	end
end

function MoneyDropService:_collect(dropId: string, player: Player)
	local record = self.drops[dropId]
	if not record or record.Collecting then
		return
	end

	-- Claim the drop before any access check can yield. DutyService:Get may wait on
	-- a Roblox group lookup; without this, two prompt callbacks can both enter the
	-- same drop before either reaches the old Collecting assignment and both credit
	-- the full amount.
	record.Collecting = true
	local function releaseClaim()
		if self.drops[dropId] == record then
			record.Collecting = false
		end
	end

	local ok, err = pcall(function()
		if self.context.Services:Get("DutyService"):Get(player) then
			releaseClaim()
			return
		end
		-- Expiry or shutdown may remove the drop while the duty check is yielding.
		-- Do not credit a record that no longer exists in the live drop table.
		if self.drops[dropId] ~= record then
			return
		end
		local position = self:_rootPosition(player)
		if
			not position
			or (position - record.Part.Position).Magnitude > self.settings.PickupDistance + 2
		then
			releaseClaim()
			return
		end
		local _, characterId = self:_activeCharacter(player)
		if not characterId then
			releaseClaim()
			return
		end
		local credited, reason = self.context.Services:Get("EconomyService"):Apply(player, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = characterId,
			Account = "Cash",
			Amount = record.Amount,
			Direction = "Credit",
			ReasonCode = "MoneyDrop.Pickup",
			Description = "Cash picked up",
			RelatedEntityId = dropId,
			Metadata = { DroppedByUserId = record.OwnerUserId },
		})
		if credited then
			self.context.Services:Get("AuditService"):Record({
				ActorUserId = player.UserId,
				CharacterId = characterId,
				Action = "MoneyDrop.PickedUp",
				Target = dropId,
				Metadata = { Amount = record.Amount, DroppedByUserId = record.OwnerUserId },
			})
			self:_remove(dropId)
		else
			releaseClaim()
			self.context.Logger:Warning("Cash pickup could not be credited", {
				DropId = dropId,
				UserId = player.UserId,
				Reason = reason,
			})
		end
	end)
	if not ok then
		releaseClaim()
		self.context.Logger:Error("Cash pickup handler failed", {
			DropId = dropId,
			UserId = player.UserId,
			Error = tostring(err),
		})
	end
end

function MoneyDropService:_create(
	dropId: string,
	amount: number,
	ownerUserId: number,
	ownerCharacterId: string,
	position: Vector3
): any
	local part = Instance.new("Part")
	part.Name = "RoleplayOSCashDrop"
	part.Size = Vector3.new(1.4, 0.25, 0.8)
	part.Color = Color3.fromRGB(86, 145, 92)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.Position = position + Vector3.new(0, 0.3, 0)
	part:SetAttribute("RoleplayOSCashDropId", dropId)
	part:SetAttribute("Amount", amount)
	part.Parent = workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RoleplayOSCashPickupPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = string.format("£%d cash", amount)
	prompt.HoldDuration = self.settings.PickupHoldSeconds
	prompt.MaxActivationDistance = self.settings.PickupDistance
	prompt.RequiresLineOfSight = true
	prompt.Parent = part

	local record = {
		Part = part,
		Amount = amount,
		OwnerUserId = ownerUserId,
		OwnerCharacterId = ownerCharacterId,
		CreatedAt = os.time(),
		Collecting = false,
	}
	self.drops[dropId] = record
	record.Connection = prompt.Triggered:Connect(function(player)
		self:_collect(dropId, player)
	end)
	record.ExpiryThread = task.delay(self.settings.LifetimeSeconds, function()
		-- This is the expiry thread itself, so clear it before _remove rather than
		-- asking _remove to cancel the currently running coroutine.
		record.ExpiryThread = nil
		self:_remove(dropId, "Expired")
	end)
	return record
end

function MoneyDropService:Drop(player: Player, amount: any): (any?, string?)
	if not self.settings.Enabled then
		return nil, "MONEY_DROPS_DISABLED"
	end
	if not self.running or not playerIsCurrent(player) then
		return nil, "MONEY_DROP_UNAVAILABLE"
	end
	if self.context.Services:Get("DutyService"):Get(player) then
		return nil, "CIVILIAN_REQUIRED"
	end
	-- DutyService:Get can yield on a group lookup. A request may outlive the
	-- shutdown drain or its Player while that happens, so do not let the stale
	-- continuation recreate a world drop after leave/teardown cleanup has run.
	if not self.running or not playerIsCurrent(player) then
		return nil, "MONEY_DROP_UNAVAILABLE"
	end
	local valid, reason = MoneyDropPolicy.validateAmount(
		amount,
		self.settings.MinimumAmount,
		self.settings.MaximumAmount
	)
	if not valid then
		return nil, reason
	end
	local character, characterId = self:_activeCharacter(player)
	local position = self:_dropPosition(player)
	if not character or not characterId then
		return nil, "ACTIVE_CHARACTER_REQUIRED"
	end
	if not position then
		return nil, "CHARACTER_UNAVAILABLE"
	end
	if amount > character.Economy.Cash then
		return nil, "INSUFFICIENT_FUNDS"
	end

	local claim, claimReason = self:_claimDropSlot(player)
	if not claim then
		return nil, claimReason
	end

	local ok, result, dropReason = pcall(function()
		local economy = self.context.Services:Get("EconomyService")
		local recovered, recoveryReason = economy:ReconcileMoneyDropRefunds(player, characterId)
		if not recovered then
			return nil, recoveryReason or "MONEY_DROP_RECOVERY_PENDING"
		end

		local dropId = HttpService:GenerateGUID(false)
		local debited, debitReason = economy:Apply(player, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = characterId,
			Account = "Cash",
			Amount = amount,
			Direction = "Debit",
			ReasonCode = "MoneyDrop.Drop",
			Description = "Cash dropped",
			RelatedEntityId = dropId,
			Metadata = {},
		})
		if not debited then
			return nil, debitReason
		end

		local created, record = pcall(function()
			return self:_create(dropId, amount, player.UserId, characterId, position)
		end)
		if not created or not record then
			local recovery = {
				DropId = dropId,
				OwnerUserId = player.UserId,
				OwnerCharacterId = characterId,
				Amount = amount,
				CreatedAt = os.time(),
			}
			local refunded, refundReason = economy:RefundMoneyDrop(player, recovery)
			local recoveredRefund = refunded or refundReason == "DUPLICATE_TRANSACTION"
			local queued = false
			local queueReason: string? = nil
			if not recoveredRefund then
				queued, queueReason = economy:QueueMoneyDropRefund(player, recovery)
			end
			self.context.Services:Get("AuditService"):Record({
				ActorUserId = player.UserId,
				CharacterId = characterId,
				Action = "MoneyDrop.CreationRefund",
				Target = dropId,
				Metadata = {
					Amount = amount,
					Refunded = recoveredRefund,
					RefundReason = refundReason,
					Queued = queued,
					QueueReason = queueReason,
				},
			})
			if not recoveredRefund and not queued then
				self.context.Logger:Error("Cash drop creation recovery could not be retained", {
					DropId = dropId,
					UserId = player.UserId,
					CharacterId = characterId,
					Amount = amount,
					RefundReason = refundReason,
					QueueReason = queueReason,
				})
			end
			return nil, "DROP_CREATION_FAILED"
		end
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			CharacterId = characterId,
			Action = "MoneyDrop.Created",
			Target = dropId,
			Metadata = { Amount = amount },
		})
		return { DropId = dropId, Amount = amount, Cash = character.Economy.Cash }, nil
	end)
	self:_releaseDropSlot(player.UserId, claim)
	if not ok then
		self.context.Logger:Error("Cash drop request failed", {
			UserId = player.UserId,
			Error = tostring(result),
		})
		return nil, "MONEY_DROP_FAILED"
	end
	return result, dropReason
end

function MoneyDropService:_recoverDrop(dropId: string, player: Player, reason: string)
	local record = self.drops[dropId]
	if not record then
		return
	end
	local recovery = recoveryRecord(dropId, record)
	self:_remove(dropId, reason)

	local economy = self.context.Services:Get("EconomyService")
	local refunded, refundReason = economy:RefundMoneyDrop(player, recovery)
	if refunded or refundReason == "DUPLICATE_TRANSACTION" then
		return
	end
	local queued, queueReason = economy:QueueMoneyDropRefund(player, recovery)
	if not queued then
		self.context.Logger:Error("Cash-drop recovery could not be retained in the profile", {
			DropId = dropId,
			UserId = record.OwnerUserId,
			CharacterId = record.OwnerCharacterId,
			Amount = record.Amount,
			RefundReason = refundReason,
			QueueReason = queueReason,
		})
	end
end

function MoneyDropService:_recoverOwnedDrops(player: Player, reason: string)
	local ids = {}
	for dropId, record in self.drops do
		if record.OwnerUserId == player.UserId then
			table.insert(ids, dropId)
		end
	end
	for _, dropId in ids do
		self:_recoverDrop(dropId, player, reason)
	end
end

function MoneyDropService:Start()
	self.running = true
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			-- Cash drops are server-local Instances and cannot safely outlive the
			-- profile session that paid for them. Recover them before DataService's
			-- deferred final save takes its snapshot.
			self:_recoverOwnedDrops(player, "OwnerLeft")
		end)
	)
end

function MoneyDropService:Destroy()
	self.running = false
	table.clear(self.dropping)
	self.pendingDrops = 0
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)

	local ids = {}
	for dropId in self.drops do
		table.insert(ids, dropId)
	end
	-- No yielding work is done here. EconomyService either restores the active
	-- character immediately or records a bounded pending refund inside the same
	-- player profile; DataService, which destroys last, persists that profile.
	for _, dropId in ids do
		local record = self.drops[dropId]
		if not record then
			continue
		end
		local owner = Players:GetPlayerByUserId(record.OwnerUserId)
		if owner then
			self:_recoverDrop(dropId, owner, "Shutdown")
		else
			-- PlayerRemoving should already have recovered this owner's drops.
			-- Reaching this branch means the lifecycle invariant was violated; the
			-- world object must still be cleaned up, but log enough to investigate.
			self:_remove(dropId, "Shutdown")
			self.context.Logger:Error("Cash drop owner was unavailable during shutdown recovery", {
				DropId = dropId,
				UserId = record.OwnerUserId,
				CharacterId = record.OwnerCharacterId,
				Amount = record.Amount,
			})
		end
	end
end

return MoneyDropService
