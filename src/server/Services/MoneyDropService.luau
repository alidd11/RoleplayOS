--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyDropPolicy = require(ReplicatedStorage.RoleplayOS.Shared.MoneyDropPolicy)

local MoneyDropService = { drops = {} }

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
	task.delay(self.settings.LifetimeSeconds, function()
		self:_remove(dropId, "Expired")
	end)
	return record
end

function MoneyDropService:Drop(player: Player, amount: any): (any?, string?)
	if not self.settings.Enabled then
		return nil, "MONEY_DROPS_DISABLED"
	end
	if self.context.Services:Get("DutyService"):Get(player) then
		return nil, "CIVILIAN_REQUIRED"
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
	local owned = 0
	for _, record in self.drops do
		if record.OwnerUserId == player.UserId then
			owned += 1
		end
	end
	if owned >= self.settings.MaximumActivePerPlayer then
		return nil, "TOO_MANY_ACTIVE_DROPS"
	end
	local activeCount = 0
	for _ in self.drops do
		activeCount += 1
	end
	if activeCount >= self.settings.MaximumActiveGlobal then
		return nil, "SERVER_DROP_LIMIT"
	end
	if amount > character.Economy.Cash then
		return nil, "INSUFFICIENT_FUNDS"
	end

	local dropId = HttpService:GenerateGUID(false)
	local debited, debitReason = self.context.Services:Get("EconomyService"):Apply(player, {
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
		local economy = self.context.Services:Get("EconomyService")
		local refunded, refundReason = economy:RefundMoneyDrop(player, recovery)
		local recovered = refunded or refundReason == "DUPLICATE_TRANSACTION"
		local queued = false
		local queueReason = nil
		if not recovered then
			queued, queueReason = economy:QueueMoneyDropRefunds({ recovery })
		end
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			CharacterId = characterId,
			Action = "MoneyDrop.CreationRefund",
			Target = dropId,
			Metadata = {
				Amount = amount,
				Refunded = recovered,
				RefundReason = refundReason,
				Queued = queued,
				QueueReason = queueReason,
			},
		})
		if not recovered and not queued then
			self.context.Logger:Error("Cash drop creation recovery could not be persisted", {
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
end

function MoneyDropService:Start() end

function MoneyDropService:Destroy()
	local ids = {}
	for dropId in self.drops do
		table.insert(ids, dropId)
	end

	local economy = self.context.Services:Get("EconomyService")
	local data = self.context.Services:Get("DataService")
	local pending: { any } = {}
	local refundsByPlayer: { [Player]: { any } } = {}

	-- Remove every world drop before the first save or shared-record write can
	-- yield. A pickup already past its final liveness check cannot interleave
	-- here; one still waiting will see the record gone and abort rather than
	-- racing a shutdown refund.
	for _, dropId in ids do
		local record = self.drops[dropId]
		if not record then
			continue
		end
		local recovery = recoveryRecord(dropId, record)
		self:_remove(dropId, "Shutdown")

		local owner = Players:GetPlayerByUserId(record.OwnerUserId)
		local activeCharacterId: string? = nil
		if owner then
			local _, currentCharacterId = self:_activeCharacter(owner)
			activeCharacterId = currentCharacterId
		end
		if owner and activeCharacterId == record.OwnerCharacterId then
			local refunded, refundReason = economy:RefundMoneyDrop(owner, recovery)
			if refunded or refundReason == "DUPLICATE_TRANSACTION" then
				local playerRefunds = refundsByPlayer[owner]
				if not playerRefunds then
					playerRefunds = {}
					refundsByPlayer[owner] = playerRefunds
				end
				table.insert(playerRefunds, recovery)
			else
				table.insert(pending, recovery)
				self.context.Logger:Warning("Cash-drop shutdown refund could not be applied", {
					DropId = dropId,
					UserId = record.OwnerUserId,
					Reason = refundReason,
				})
			end
		else
			table.insert(pending, recovery)
		end
	end

	-- Persist once per affected owner, not once per drop. If this save loses a
	-- race with another save or fails transiently, the same deterministic refund
	-- is queued below and can be retried safely on a later session.
	for player, records in refundsByPlayer do
		local saved, saveReason = data:Save(player)
		if saved then
			for _, record in records do
				self.context.Services:Get("AuditService"):Record({
					ActorUserId = player.UserId,
					CharacterId = record.OwnerCharacterId,
					Action = "MoneyDrop.ShutdownRefunded",
					Target = record.DropId,
					Metadata = { Amount = record.Amount },
				})
			end
		else
			for _, record in records do
				table.insert(pending, record)
			end
			self.context.Logger:Warning("Cash-drop shutdown refunds could not be saved", {
				UserId = player.UserId,
				Count = #records,
				Reason = saveReason,
			})
		end
	end

	if #pending > 0 then
		local queued, queueReason = economy:QueueMoneyDropRefunds(pending)
		if not queued then
			self.context.Logger:Error("Cash-drop shutdown recovery queue failed", {
				Count = #pending,
				Reason = queueReason,
			})
		end
	end
end

return MoneyDropService
