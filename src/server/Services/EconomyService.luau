--!strict

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Validator = require(ReplicatedStorage.RoleplayOS.Shared.EconomyValidator)
local HttpService = game:GetService("HttpService")

local EconomyService = {
	seen = {},
	order = {},
	transferring = {},
	connections = {},
	reconciling = {},
	running = false,
}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function transactionScope(userId: number, characterId: string): string
	return tostring(userId) .. ":" .. characterId
end

local function pendingTransferEntryId(entry: any): string?
	if type(entry) == "string" then
		return entry
	end
	if type(entry) == "table" and type(entry.Id) == "string" and entry.Id ~= "" then
		return entry.Id
	end
	return nil
end

local function pendingTransferEntryRecord(entry: any): any?
	if type(entry) == "table" and type(entry.Record) == "table" then
		return entry.Record
	end
	return nil
end
function EconomyService:Init(context: any)
	self.context = context
	table.clear(self.reconciling)
end
function EconomyService:Start()
	self.running = true
	-- The in-progress marker is cleared when a player leaves as well as on every
	-- exit from Transfer. Anything raising between setting and clearing it would
	-- otherwise leave that player unable to send money for the rest of the
	-- server's life, since the table was only emptied on shutdown.
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.transferring[player.UserId] = nil
			local prefix = tostring(player.UserId) .. ":"
			for key in self.seen do
				if string.sub(key, 1, #prefix) == prefix then
					self.seen[key] = nil
					self.order[key] = nil
				end
			end
			for key in self.reconciling do
				if string.sub(key, 1, #prefix) == prefix then
					self.reconciling[key] = nil
				end
			end
		end)
	)

	-- Profile load happens before character selection, so a recovery pass that
	-- runs as soon as GetSession succeeds cannot see the character that owns the
	-- refund. Wait briefly for selection here as a fallback; CharacterService
	-- also invokes the same targeted pass at the selection boundary.
	local function reconcileWhenReady(player: Player)
		task.spawn(function()
			local deadline = os.clock() + 15
			local data = self.context.Services:Get("DataService")
			local session = data:GetSession(player)
			while
				self.running
				and playerIsCurrent(player)
				and (not session or not session.ActiveCharacterId)
				and os.clock() < deadline
			do
				task.wait(0.25)
				session = data:GetSession(player)
			end
			local characterId = session and session.ActiveCharacterId
			if self.running and playerIsCurrent(player) and characterId then
				self:ReconcilePendingTransfers(player, characterId)
			end
		end)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(reconcileWhenReady))
	for _, player in Players:GetPlayers() do
		reconcileWhenReady(player)
	end
end

function EconomyService:_queuePendingRefund(record: any)
	local data = self.context.Services:Get("DataService")
	local id = "pt:" .. record.TransferId
	-- Store the recovery payload in the discoverable index itself. The previous
	-- two-write shape persisted pt:<id> first and indexed it second; if the first
	-- UpdateAsync succeeded and the index write failed, the refund became a
	-- durable orphan that no server could discover again.
	local _, indexReason = data:UpdateSharedRecord("pending-transfer-index", function(existing)
		local index = if type(existing) == "table" then existing else {}
		for _, entry in index do
			if pendingTransferEntryId(entry) == id then
				return index
			end
		end
		table.insert(index, {
			Id = id,
			Record = record,
		})
		return index
	end)
	if indexReason then
		self.context.Logger:Error("Pending transfer recovery persistence failed", {
			TransferId = record.TransferId,
			Error = indexReason,
		})
	end
end

function EconomyService:QueueMoneyDropRefund(player: Player, record: any): (boolean, string?)
	if not self.running then
		return false, "ECONOMY_UNAVAILABLE"
	end
	if
		type(record) ~= "table"
		or record.OwnerUserId ~= player.UserId
		or type(record.DropId) ~= "string"
		or record.DropId == ""
		or type(record.OwnerCharacterId) ~= "string"
		or record.OwnerCharacterId == ""
		or type(record.Amount) ~= "number"
		or record.Amount <= 0
		or record.Amount ~= math.floor(record.Amount)
	then
		return false, "INVALID_MONEY_DROP_REFUND"
	end

	local data = self.context.Services:Get("DataService")
	local session = data:GetSession(player)
	local character = session and session.Profile.Characters[record.OwnerCharacterId]
	if not character then
		return false, "CHARACTER_NOT_OWNED"
	end
	local economy = character.Economy
	local pending = economy.PendingCashDropRefunds
	if type(pending) ~= "table" then
		pending = {}
		economy.PendingCashDropRefunds = pending
	end
	if pending[record.DropId] == nil then
		local count = 0
		for _ in pending do
			count += 1
		end
		if count >= self.context.Configuration.MoneyDrops.MaximumActivePerPlayer then
			return false, "MONEY_DROP_REFUND_QUEUE_FULL"
		end
	end
	pending[record.DropId] = {
		DropId = record.DropId,
		Amount = record.Amount,
		CreatedAt = record.CreatedAt or os.time(),
	}
	data:MarkDirty(player)
	return true, nil
end

function EconomyService:RefundMoneyDrop(player: Player, record: any): (boolean, string?)
	if
		type(record) ~= "table"
		or record.OwnerUserId ~= player.UserId
		or type(record.DropId) ~= "string"
		or type(record.OwnerCharacterId) ~= "string"
		or type(record.Amount) ~= "number"
	then
		return false, "INVALID_MONEY_DROP_REFUND"
	end
	return self:Apply(player, {
		TransactionId = "money-drop-refund:" .. record.DropId,
		CharacterId = record.OwnerCharacterId,
		Account = "Cash",
		Amount = record.Amount,
		Direction = "Credit",
		ReasonCode = "MoneyDrop.RecoveryRefund",
		Description = "Recovered cash drop",
		RelatedEntityId = record.DropId,
		Metadata = {},
	})
end

function EconomyService:ReconcileMoneyDropRefunds(
	player: Player,
	characterId: string
): (boolean, string?)
	if not self.running or not playerIsCurrent(player) then
		return false, "ECONOMY_UNAVAILABLE"
	end
	local data = self.context.Services:Get("DataService")
	local session = data:GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character or session.ActiveCharacterId ~= characterId then
		return false, "CHARACTER_NOT_ACTIVE"
	end
	local economy = character.Economy
	local pending = economy.PendingCashDropRefunds
	if type(pending) ~= "table" then
		economy.PendingCashDropRefunds = {}
		data:MarkDirty(player)
		return true, nil
	end

	local completed: { any } = {}
	local unresolvedReason: string? = nil
	for dropId, record in pending do
		local valid = type(dropId) == "string"
			and type(record) == "table"
			and record.DropId == dropId
			and type(record.Amount) == "number"
			and record.Amount > 0
			and record.Amount == math.floor(record.Amount)
		if not valid then
			table.insert(completed, dropId)
			self.context.Logger:Error("Discarding malformed pending cash-drop refund", {
				UserId = player.UserId,
				CharacterId = characterId,
				DropId = tostring(dropId),
			})
			continue
		end
		local refunded, refundReason = self:RefundMoneyDrop(player, {
			DropId = dropId,
			OwnerUserId = player.UserId,
			OwnerCharacterId = characterId,
			Amount = record.Amount,
		})
		if refunded or refundReason == "DUPLICATE_TRANSACTION" then
			table.insert(completed, dropId)
		elseif unresolvedReason == nil then
			unresolvedReason = refundReason or "MONEY_DROP_REFUND_FAILED"
		end
	end

	for _, dropId in completed do
		pending[dropId] = nil
	end
	if #completed > 0 then
		data:MarkDirty(player)
	end
	if unresolvedReason then
		return false, unresolvedReason
	end
	return true, nil
end

function EconomyService:_transactionState(
	character: any,
	scope: string
): ({ [string]: boolean }, { string })
	local existingSeen = self.seen[scope]
	local existingOrder = self.order[scope]
	if existingSeen and existingOrder then
		return existingSeen, existingOrder
	end

	-- Rebuild the volatile replay guard from the profile's durable transaction
	-- history. Without this, hopping servers forgot every transaction id and a
	-- recovery path using a stable id could apply the same balance change again.
	local seen: { [string]: boolean } = {}
	local order: { string } = {}
	for _, transaction in character.Economy.Transactions or {} do
		local transactionId = if type(transaction) == "table"
			then transaction.TransactionId
			else nil
		if type(transactionId) == "string" and transactionId ~= "" and not seen[transactionId] then
			seen[transactionId] = true
			table.insert(order, transactionId)
		end
	end
	local maximum = self.context.Configuration.Economy.MaximumTransactionHistory or 200
	while #order > maximum do
		local oldest = table.remove(order, 1)
		if oldest then
			seen[oldest] = nil
		end
	end
	self.seen[scope] = seen
	self.order[scope] = order
	return seen, order
end

function EconomyService:ReconcilePendingTransfers(
	player: Player,
	characterId: string
): (boolean, string?)
	if not self.running or not playerIsCurrent(player) then
		return false, "ECONOMY_UNAVAILABLE"
	end
	local data = self.context.Services:Get("DataService")
	local session = data:GetSession(player)
	if not session or session.ActiveCharacterId ~= characterId then
		return false, "CHARACTER_NOT_ACTIVE"
	end
	local scope = transactionScope(player.UserId, characterId)
	if self.reconciling[scope] then
		return false, "TRANSFER_RECOVERY_IN_PROGRESS"
	end
	self.reconciling[scope] = true

	local unresolvedReason: string? = nil
	local ok, problem = pcall(function()
		local index, indexReason = data:GetSharedRecord("pending-transfer-index")
		if indexReason then
			unresolvedReason = indexReason
			return
		end
		if
			not self.running
			or not playerIsCurrent(player)
			or data:GetSession(player) ~= session
			or session.ActiveCharacterId ~= characterId
		then
			unresolvedReason = "CHARACTER_NOT_ACTIVE"
			return
		end
		if type(index) ~= "table" then
			return
		end

		local completed: { [string]: boolean } = {}
		for _, entry in index do
			if
				not self.running
				or not playerIsCurrent(player)
				or data:GetSession(player) ~= session
				or session.ActiveCharacterId ~= characterId
			then
				unresolvedReason = "CHARACTER_NOT_ACTIVE"
				return
			end

			local id = pendingTransferEntryId(entry)
			if not id then
				self.context.Logger:Error("Pending transfer index contains an invalid entry", {})
				continue
			end

			local embeddedRecord = pendingTransferEntryRecord(entry)
			local record = embeddedRecord
			if not record then
				local recordReason
				record, recordReason = data:GetSharedRecord(id)
				if recordReason then
					unresolvedReason = unresolvedReason or recordReason
					continue
				end
				if
					not self.running
					or not playerIsCurrent(player)
					or data:GetSession(player) ~= session
					or session.ActiveCharacterId ~= characterId
				then
					unresolvedReason = "CHARACTER_NOT_ACTIVE"
					return
				end
				-- Legacy entries wrote the record before the index. A string whose
				-- record is now absent is therefore stale cleanup, not a recoverable
				-- debt that should remain in the index forever.
				if record == nil and type(entry) == "string" then
					completed[id] = true
					continue
				end
			end
			if type(record) ~= "table" then
				self.context.Logger:Error("Pending transfer recovery record is invalid", {
					RecoveryId = id,
				})
				continue
			end
			if record.SenderUserId ~= player.UserId or record.SenderCharacterId ~= characterId then
				continue
			end
			if record.Status == "Reconciled" then
				completed[id] = true
				continue
			end
			if
				type(record.TransferId) ~= "string"
				or record.TransferId == ""
				or type(record.Amount) ~= "number"
				or record.Amount <= 0
				or record.Amount ~= math.floor(record.Amount)
			then
				self.context.Logger:Error("Pending transfer refund is malformed", {
					RecoveryId = id,
					UserId = player.UserId,
					CharacterId = characterId,
				})
				continue
			end

			local refundTransactionId = "transfer-refund-reconcile:" .. id
			local applied, applyReason = self:Apply(player, {
				TransactionId = refundTransactionId,
				CharacterId = characterId,
				Amount = record.Amount,
				Direction = "Credit",
				ReasonCode = "PLAYER_TRANSFER_REFUND_RECONCILE",
				Description = "Recovered transfer refund",
				RelatedEntityId = record.TransferId,
				Metadata = {},
			})
			if not applied and applyReason ~= "DUPLICATE_TRANSACTION" then
				unresolvedReason = unresolvedReason or applyReason or "TRANSFER_REFUND_FAILED"
				continue
			end

			-- A duplicate means this deterministic refund is already in the loaded
			-- transaction history. Save again before retiring the recovery record:
			-- a prior UpdateAsync failure is ambiguous and may have committed.
			local saved, saveReason = data:Save(player)
			if
				not self.running
				or not playerIsCurrent(player)
				or data:GetSession(player) ~= session
				or session.ActiveCharacterId ~= characterId
			then
				unresolvedReason = "CHARACTER_NOT_ACTIVE"
				return
			end
			if not saved then
				unresolvedReason = unresolvedReason or saveReason or "PROFILE_SAVE_FAILED"
				self.context.Logger:Warning("Pending transfer refund save failed", {
					TransferId = record.TransferId,
					UserId = player.UserId,
					Error = saveReason,
				})
				continue
			end

			local _, recordReason
			if embeddedRecord then
				_, recordReason = data:UpdateSharedRecord(
					"pending-transfer-index",
					function(existing)
						if type(existing) ~= "table" then
							return existing
						end
						for _, currentEntry in existing do
							if pendingTransferEntryId(currentEntry) == id then
								local currentRecord = pendingTransferEntryRecord(currentEntry)
								if currentRecord then
									currentRecord.Status = "Reconciled"
									currentRecord.ReconciledAt = os.time()
									currentRecord.RefundTransactionId = refundTransactionId
								end
								break
							end
						end
						return existing
					end
				)
			else
				_, recordReason = data:UpdateSharedRecord(id, function(existing)
					if type(existing) == "table" then
						existing.Status = "Reconciled"
						existing.ReconciledAt = os.time()
						existing.RefundTransactionId = refundTransactionId
					end
					return existing
				end)
			end
			if recordReason then
				unresolvedReason = unresolvedReason or recordReason
				self.context.Logger:Error("Pending transfer refund receipt persistence failed", {
					TransferId = record.TransferId,
					Error = recordReason,
				})
			else
				completed[id] = true
			end
		end

		if next(completed) == nil then
			return
		end
		local _, cleanupReason = data:UpdateSharedRecord(
			"pending-transfer-index",
			function(existing)
				if type(existing) ~= "table" then
					return existing
				end
				local current = {}
				for _, entry in existing do
					local id = pendingTransferEntryId(entry)
					if not id or not completed[id] then
						table.insert(current, entry)
					end
				end
				return current
			end
		)
		if cleanupReason then
			unresolvedReason = unresolvedReason or cleanupReason
			self.context.Logger:Error("Pending transfer refund index persistence failed", {
				Error = cleanupReason,
			})
		end
	end)

	self.reconciling[scope] = nil
	if not ok then
		self.context.Logger:Error("Pending transfer reconciliation failed", {
			UserId = player.UserId,
			CharacterId = characterId,
			Error = tostring(problem),
		})
		return false, "TRANSFER_RECOVERY_FAILED"
	end
	if unresolvedReason then
		return false, unresolvedReason
	end
	return true, nil
end
function EconomyService:Apply(player: Player, transaction: any): (boolean, string?)
	if not self.running or not playerIsCurrent(player) then
		return false, "ECONOMY_UNAVAILABLE"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[transaction.CharacterId]
	if not character or session.ActiveCharacterId ~= transaction.CharacterId then
		return false, "CHARACTER_NOT_ACTIVE"
	end
	local scope = transactionScope(player.UserId, transaction.CharacterId)
	local seen, order = self:_transactionState(character, scope)
	local account, accountReason = Validator.account(transaction.Account)
	if not account then
		return false, accountReason
	end
	local currentBalance = if account == "Cash"
		then character.Economy.Cash
		else character.Economy.Balance
	local valid, reason = Validator.transaction(transaction, seen, currentBalance)
	if not valid then
		return false, reason
	end
	seen[transaction.TransactionId] = true
	-- Bounded. Identifiers are server generated GUIDs used once, so this only
	-- needs to be long enough that a replay cannot outrun it; keeping every
	-- identifier a character ever used grows for the life of the server.
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
	transaction.Account = account
	transaction.Metadata = transaction.Metadata or {}
	if transaction.Direction == "Credit" then
		if account == "Cash" then
			character.Economy.Cash += transaction.Amount
		else
			character.Economy.Balance += transaction.Amount
		end
	else
		if account == "Cash" then
			character.Economy.Cash -= transaction.Amount
		else
			character.Economy.Balance -= transaction.Amount
		end
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
			Account = account,
			Amount = transaction.Amount,
			Direction = transaction.Direction,
			ReasonCode = transaction.ReasonCode,
		},
	})
	return true, nil
end

-- Moves bank funds between two active characters in this server. The client
-- supplies neither character id nor balance; both are resolved again here.
function EconomyService:_transfer(
	sender: Player,
	recipient: Player,
	amount: any,
	maximumAmount: number?,
	buildDefinition: (any, any) -> any
): (any?, string?)
	if not self.running or not playerIsCurrent(sender) or not playerIsCurrent(recipient) then
		return nil, "ECONOMY_UNAVAILABLE"
	end
	if sender == recipient then
		return nil, "SELF_TRANSFER"
	end
	local valid, reason = Validator.amount(amount)
	if not valid then
		return nil, reason
	end
	if maximumAmount and amount > maximumAmount then
		return nil, "TRANSFER_LIMIT"
	end

	-- Acquire both locks in ascending UserId order, and check/set them without a
	-- yield. Luau code is single-threaded between yields, so opposing A→B and
	-- B→A requests cannot both pass the check and then deadlock each other.
	local firstUserId = math.min(sender.UserId, recipient.UserId)
	local secondUserId = math.max(sender.UserId, recipient.UserId)
	if self.transferring[firstUserId] or self.transferring[secondUserId] then
		return nil, "TRANSFER_IN_PROGRESS"
	end
	self.transferring[firstUserId] = true
	self.transferring[secondUserId] = true
	local function releaseTransferLocks()
		self.transferring[sender.UserId] = nil
		self.transferring[recipient.UserId] = nil
	end

	local data = self.context.Services:Get("DataService")
	local senderSession = data:GetSession(sender)
	local recipientSession = data:GetSession(recipient)
	local senderId = senderSession and senderSession.ActiveCharacterId
	local recipientId = recipientSession and recipientSession.ActiveCharacterId
	local senderCharacter = senderId and senderSession.Profile.Characters[senderId]
	local recipientCharacter = recipientId and recipientSession.Profile.Characters[recipientId]
	if not senderCharacter then
		releaseTransferLocks()
		return nil, "ACTIVE_CHARACTER_REQUIRED"
	end
	if not recipientCharacter then
		releaseTransferLocks()
		return nil, "PHONE_RECIPIENT_UNAVAILABLE"
	end
	if amount > senderCharacter.Economy.Balance then
		releaseTransferLocks()
		return nil, "INSUFFICIENT_FUNDS"
	end

	local transferId = HttpService:GenerateGUID(false)
	local definition = buildDefinition(senderCharacter, recipientCharacter)
	local recipientName = recipientCharacter.Identity.FirstName
		.. " "
		.. recipientCharacter.Identity.LastName

	local debited, debitReason = self:Apply(sender, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = senderId,
		Amount = amount,
		Direction = "Debit",
		ReasonCode = definition.DebitReasonCode,
		Description = definition.DebitDescription,
		RelatedEntityId = transferId,
		Metadata = definition.DebitMetadata or {},
	})
	if not debited then
		releaseTransferLocks()
		return nil, debitReason
	end

	local credited, creditReason = self:Apply(recipient, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = recipientId,
		Amount = amount,
		Direction = "Credit",
		ReasonCode = definition.CreditReasonCode,
		Description = definition.CreditDescription,
		RelatedEntityId = transferId,
		Metadata = definition.CreditMetadata or {},
	})
	if not credited then
		local refunded, refundReason = self:Apply(sender, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = senderId,
			Amount = amount,
			Direction = "Credit",
			ReasonCode = definition.RefundReasonCode,
			Description = definition.RefundDescription,
			RelatedEntityId = transferId,
			Metadata = definition.RefundMetadata or {},
		})
		-- Persist the restored balance before another transfer may use it.
		if refunded then
			data:Save(sender)
		end
		releaseTransferLocks()
		if not refunded then
			self:_queuePendingRefund({
				TransferId = transferId,
				SenderUserId = sender.UserId,
				SenderCharacterId = senderId,
				Amount = amount,
				CreatedAt = os.time(),
				Status = "Pending",
			})
			self.context.Logger:Error("Economy transfer refund failed", {
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

	-- Both halves are written now, and the recipient's first. The two people
	-- live under separate DataStore keys, so this narrows the split-write window
	-- from an autosave interval to two immediate saves. A durable cross-profile
	-- ledger is still the long-term route to true atomicity.
	local recipientSaved = data:Save(recipient)
	local senderSaved = data:Save(sender)
	if not recipientSaved or not senderSaved then
		self.context.Logger:Error("Economy transfer may not have persisted on both sides", {
			TransferId = transferId,
			Amount = amount,
			SenderUserId = sender.UserId,
			SenderCharacterId = senderId,
			SenderSaved = senderSaved,
			RecipientUserId = recipient.UserId,
			RecipientCharacterId = recipientId,
			RecipientSaved = recipientSaved,
			Kind = definition.Kind,
		})
	end
	releaseTransferLocks()

	return {
		TransferId = transferId,
		Amount = amount,
		Recipient = recipientName,
		Balance = senderCharacter.Economy.Balance,
	},
		nil
end

-- Player-initiated bank transfer. The client supplies only the recipient and
-- amount; all transaction semantics remain server-owned here.
function EconomyService:Transfer(sender: Player, recipient: Player, amount: any): (any?, string?)
	return self:_transfer(
		sender,
		recipient,
		amount,
		self.context.Configuration.Economy.TransferMaximum,
		function(senderCharacter, recipientCharacter)
			local recipientName = recipientCharacter.Identity.FirstName
				.. " "
				.. recipientCharacter.Identity.LastName
			local senderName = senderCharacter.Identity.FirstName
				.. " "
				.. senderCharacter.Identity.LastName
			return {
				Kind = "PlayerTransfer",
				DebitReasonCode = "PLAYER_TRANSFER_SENT",
				DebitDescription = "Transfer to " .. recipientName,
				DebitMetadata = { RecipientUserId = recipient.UserId },
				CreditReasonCode = "PLAYER_TRANSFER_RECEIVED",
				CreditDescription = "Transfer from " .. senderName,
				CreditMetadata = { SenderUserId = sender.UserId },
				RefundReasonCode = "PLAYER_TRANSFER_REFUND",
				RefundDescription = "Automatic transfer refund",
				RefundMetadata = {},
			}
		end
	)
end

-- Server-owned taxi settlement. TaxiService proves the journey and supplies the
-- configured fare; EconomyService owns the actual two-profile money movement.
function EconomyService:PayTaxiFare(
	passenger: Player,
	driver: Player,
	amount: any,
	taxiId: string,
	dropoff: string
): (any?, string?)
	if taxiId == "" or #taxiId > 128 or #dropoff > 80 then
		return nil, "INVALID_TAXI_FARE"
	end
	return self:_transfer(passenger, driver, amount, nil, function(senderCharacter)
		local passengerName = senderCharacter.Identity.FirstName
			.. " "
			.. senderCharacter.Identity.LastName
		return {
			Kind = "TaxiFare",
			DebitReasonCode = "TAXI_FARE",
			DebitDescription = "Taxi fare to " .. dropoff,
			DebitMetadata = { TaxiId = taxiId, DriverUserId = driver.UserId },
			CreditReasonCode = "TAXI_FARE_RECEIVED",
			CreditDescription = "Taxi fare from " .. passengerName,
			CreditMetadata = { TaxiId = taxiId, PassengerUserId = passenger.UserId },
			RefundReasonCode = "TAXI_FARE_REFUND",
			RefundDescription = "Taxi fare refund",
			RefundMetadata = { TaxiId = taxiId },
		}
	end)
end

function EconomyService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.seen)
	table.clear(self.order)
	table.clear(self.transferring)
	table.clear(self.reconciling)
end
return EconomyService
