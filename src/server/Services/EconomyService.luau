--!strict

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Validator = require(ReplicatedStorage.RoleplayOS.Shared.EconomyValidator)
local HttpService = game:GetService("HttpService")

local EconomyService = { seen = {}, order = {}, transferring = {}, connections = {} }
function EconomyService:Init(context: any)
	self.context = context
end
function EconomyService:Start()
	-- The in-progress marker is cleared when a player leaves as well as on every
	-- exit from Transfer. Anything raising between setting and clearing it would
	-- otherwise leave that player unable to send money for the rest of the
	-- server's life, since the table was only emptied on shutdown.
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.transferring[player.UserId] = nil
			self.seen[player.UserId] = nil
		end)
	)
end
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
	-- Bounded. Identifiers are server generated GUIDs used once, so this only
	-- needs to be long enough that a replay cannot outrun it; keeping every
	-- identifier a character ever used grows for the life of the server.
	local order = self.order[transaction.CharacterId] or {}
	self.order[transaction.CharacterId] = order
	table.insert(order, transaction.TransactionId)
	local maximum = self.context.Configuration.Economy.MaximumTransactionHistory or 200
	while #order > maximum do
		local oldest = table.remove(order, 1)
		if oldest then
			seen[oldest] = nil
		end
	end
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

-- Moves bank funds between two active characters in this server. The client
-- supplies neither character id nor balance; both are resolved again here.
function EconomyService:Transfer(sender: Player, recipient: Player, amount: any): (any?, string?)
	if sender == recipient then
		return nil, "SELF_TRANSFER"
	end
	local valid, reason = Validator.amount(amount)
	if not valid then
		return nil, reason
	end
	if amount > self.context.Configuration.Economy.TransferMaximum then
		return nil, "TRANSFER_LIMIT"
	end
	if self.transferring[sender.UserId] then
		return nil, "TRANSFER_IN_PROGRESS"
	end
	local data = self.context.Services:Get("DataService")
	local senderSession = data:GetSession(sender)
	local recipientSession = data:GetSession(recipient)
	local senderId = senderSession and senderSession.ActiveCharacterId
	local recipientId = recipientSession and recipientSession.ActiveCharacterId
	local senderCharacter = senderId and senderSession.Profile.Characters[senderId]
	local recipientCharacter = recipientId and recipientSession.Profile.Characters[recipientId]
	if not senderCharacter then
		return nil, "ACTIVE_CHARACTER_REQUIRED"
	end
	if not recipientCharacter then
		return nil, "PHONE_RECIPIENT_UNAVAILABLE"
	end
	if amount > senderCharacter.Economy.Balance then
		return nil, "INSUFFICIENT_FUNDS"
	end

	self.transferring[sender.UserId] = true
	local transferId = HttpService:GenerateGUID(false)
	local recipientName = recipientCharacter.Identity.FirstName
		.. " "
		.. recipientCharacter.Identity.LastName
	local senderName = senderCharacter.Identity.FirstName
		.. " "
		.. senderCharacter.Identity.LastName
	local debited, debitReason = self:Apply(sender, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = senderId,
		Amount = amount,
		Direction = "Debit",
		ReasonCode = "PLAYER_TRANSFER_SENT",
		Description = "Transfer to " .. recipientName,
		RelatedEntityId = transferId,
		Metadata = { RecipientUserId = recipient.UserId },
	})
	if not debited then
		self.transferring[sender.UserId] = nil
		return nil, debitReason
	end
	local credited, creditReason = self:Apply(recipient, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = recipientId,
		Amount = amount,
		Direction = "Credit",
		ReasonCode = "PLAYER_TRANSFER_RECEIVED",
		Description = "Transfer from " .. senderName,
		RelatedEntityId = transferId,
		Metadata = { SenderUserId = sender.UserId },
	})
	if not credited then
		local refunded, refundReason = self:Apply(sender, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = senderId,
			Amount = amount,
			Direction = "Credit",
			ReasonCode = "PLAYER_TRANSFER_REFUND",
			Description = "Automatic transfer refund",
			RelatedEntityId = transferId,
			Metadata = {},
		})
		self.transferring[sender.UserId] = nil
		if not refunded then
			self.context.Logger:Error("Player transfer refund failed", {
				SenderUserId = sender.UserId,
				RecipientUserId = recipient.UserId,
				Amount = amount,
				TransferId = transferId,
				CreditError = creditReason,
				RefundError = refundReason,
			})
		end
		return nil, creditReason
	end
	self.transferring[sender.UserId] = nil

	-- Both halves are written now, and the recipient's first.
	--
	-- The two people live under separate DataStore keys, so a transfer that is
	-- perfectly atomic in memory is not atomic on disk. Left to the autosave,
	-- either could be written up to a minute later or not at all: if the
	-- recipient's lands and the sender's does not, money has been created, and
	-- the reverse destroys it.
	--
	-- Writing immediately shrinks that window from a minute to the length of two
	-- calls. Recipient first, deliberately, because the orders of failure are not
	-- equally bad: a transfer that vanishes can be given back from the line
	-- below, while one that doubles is loose in the economy for good and there is
	-- nothing to take it from.
	--
	-- This is a narrowing, not a fix. Making it truly atomic needs a ledger both
	-- profiles are reconciled against, which is a bigger change than this is.
	local recipientSaved = data:Save(recipient)
	local senderSaved = data:Save(sender)
	if not recipientSaved or not senderSaved then
		-- Everything needed to put it right by hand, in one line, because the
		-- audit trail is an in-memory ring that does not survive the shutdown
		-- this would most likely be discovered after.
		self.context.Logger:Error("Player transfer may not have persisted on both sides", {
			TransferId = transferId,
			Amount = amount,
			SenderUserId = sender.UserId,
			SenderCharacterId = senderId,
			SenderSaved = senderSaved,
			RecipientUserId = recipient.UserId,
			RecipientCharacterId = recipientId,
			RecipientSaved = recipientSaved,
		})
	end

	return {
		TransferId = transferId,
		Amount = amount,
		Recipient = recipientName,
		Balance = senderCharacter.Economy.Balance,
	},
		nil
end
function EconomyService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.seen)
	table.clear(self.order)
	table.clear(self.transferring)
end
return EconomyService
