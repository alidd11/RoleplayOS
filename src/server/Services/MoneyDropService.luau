--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyDropPolicy = require(ReplicatedStorage.RoleplayOS.Shared.MoneyDropPolicy)

local MoneyDropService = { drops = {} }

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
	if self.context.Services:Get("DutyService"):Get(player) then
		return
	end
	local position = self:_rootPosition(player)
	if
		not position
		or (position - record.Part.Position).Magnitude > self.settings.PickupDistance + 2
	then
		return
	end
	local _, characterId = self:_activeCharacter(player)
	if not characterId then
		return
	end
	record.Collecting = true
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
		record.Collecting = false
		self.context.Logger:Warning("Cash pickup could not be credited", {
			DropId = dropId,
			UserId = player.UserId,
			Reason = reason,
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
		local refunded, refundReason = self.context.Services:Get("EconomyService"):Apply(player, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = characterId,
			Account = "Cash",
			Amount = amount,
			Direction = "Credit",
			ReasonCode = "MoneyDrop.CreationRefund",
			Description = "Failed cash drop refunded",
			RelatedEntityId = dropId,
			Metadata = {},
		})
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			CharacterId = characterId,
			Action = "MoneyDrop.CreationRefund",
			Target = dropId,
			Metadata = { Amount = amount, Refunded = refunded, Reason = refundReason },
		})
		if not refunded then
			self.context.Logger:Error("Cash drop creation refund failed", {
				DropId = dropId,
				UserId = player.UserId,
				CharacterId = characterId,
				Amount = amount,
				Reason = refundReason,
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
	for _, dropId in ids do
		self:_remove(dropId)
	end
end

return MoneyDropService
