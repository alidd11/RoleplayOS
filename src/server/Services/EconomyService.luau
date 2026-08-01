--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Validator = require(ReplicatedStorage.RoleplayOS.Shared.EconomyValidator)
local EconomyService = { seen = {} }
function EconomyService:Init(context: any)
	self.context = context
end
function EconomyService:Start() end
function EconomyService:Apply(player: Player, transaction: any): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[transaction.CharacterId]
	if not character or session.ActiveCharacterId ~= transaction.CharacterId then
		return false, "CHARACTER_NOT_ACTIVE"
	end
	local seen = self.seen[transaction.CharacterId] or {}
	self.seen[transaction.CharacterId] = seen
	local valid, reason = Validator.transaction(transaction, seen, character.Economy.Balance)
	if not valid then
		return false, reason
	end
	seen[transaction.TransactionId] = true
	transaction.Timestamp = os.time()
	transaction.Result = "Applied"
	transaction.Metadata = transaction.Metadata or {}
	if transaction.Direction == "Credit" then
		character.Economy.Balance += transaction.Amount
	else
		character.Economy.Balance -= transaction.Amount
	end
	table.insert(character.Economy.Transactions, transaction)
	while
		#character.Economy.Transactions
		> self.context.Configuration.Economy.MaximumTransactionHistory
	do
		table.remove(character.Economy.Transactions, 1)
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		CharacterId = transaction.CharacterId,
		Action = "Economy.Transaction",
		Target = transaction.RelatedEntityId or transaction.CharacterId,
		Metadata = {
			Amount = transaction.Amount,
			Direction = transaction.Direction,
			ReasonCode = transaction.ReasonCode,
		},
	})
	return true, nil
end
function EconomyService:Destroy()
	table.clear(self.seen)
end
return EconomyService
