--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contract = require(ReplicatedStorage.RoleplayOS.Shared.TransferSettlement)

local EconomySettlement = {}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function clearPending(service: any, userId: number, transferId: string)
	if service.settlementPending[userId] == transferId then
		service.settlementPending[userId] = nil
	end
end

local function setPending(service: any, record: any)
	service.settlementPending[record.Sender.UserId] = record.TransferId
	service.settlementPending[record.Recipient.UserId] = record.TransferId
end

local function transactionState(character: any, record: any, side: string): (boolean, boolean)
	local expected = record[side].Transaction
	local direction = if side == "Sender" then "Debit" else "Credit"
	for _, transaction in character.Economy.Transactions or {} do
		if type(transaction) == "table" and transaction.TransactionId == expected.TransactionId then
			local matches = transaction.Amount == record.Amount
				and transaction.Direction == direction
				and transaction.RelatedEntityId == record.TransferId
				and transaction.ReasonCode == expected.ReasonCode
			return matches, true
		end
	end
	return false, false
end

local function deleteRecord(
	service: any,
	userId: number,
	transferId: string,
	preparedOnly: boolean?
): (boolean, string?)
	local data = service.context.Services:Get("DataService")
	local removed = false
	local _, reason = data:UpdateSharedRecord(Contract.recordKey(userId), function(existing)
		if
			Contract.valid(existing)
			and existing.TransferId == transferId
			and (preparedOnly ~= true or existing.Decision == "Prepared")
		then
			removed = true
			return nil
		end
		return existing
	end)
	if reason then
		return false, reason
	end
	return removed, nil
end

local function abortPrepared(service: any, record: any): boolean
	local senderRemoved, senderReason =
		deleteRecord(service, record.Sender.UserId, record.TransferId, true)
	local recipientRemoved, recipientReason =
		deleteRecord(service, record.Recipient.UserId, record.TransferId, true)
	if senderReason or recipientReason then
		return false
	end
	if senderRemoved then
		clearPending(service, record.Sender.UserId, record.TransferId)
	end
	if recipientRemoved then
		clearPending(service, record.Recipient.UserId, record.TransferId)
	end
	return true
end

local function writePrepared(
	service: any,
	userId: number,
	expected: any
): (any?, string?)
	local data = service.context.Services:Get("DataService")
	local updated, reason = data:UpdateSharedRecord(Contract.recordKey(userId), function(existing)
		if existing == nil then
			return expected
		end
		return existing
	end)
	if reason then
		return nil, reason
	end
	if
		not Contract.matches(updated, expected)
		or updated.OwnerSide ~= expected.OwnerSide
	then
		return nil, "TRANSFER_SETTLEMENT_PENDING"
	end
	return updated, nil
end

local function currentCommitState(
	service: any,
	sender: Player,
	recipient: Player,
	record: any
): (boolean, string?)
	if not service.running or not playerIsCurrent(sender) or not playerIsCurrent(recipient) then
		return false, "ECONOMY_UNAVAILABLE"
	end
	local data = service.context.Services:Get("DataService")
	local senderSession = data:GetSession(sender)
	local recipientSession = data:GetSession(recipient)
	if
		not senderSession
		or senderSession.ActiveCharacterId ~= record.Sender.CharacterId
		or not senderSession.Profile.Characters[record.Sender.CharacterId]
	then
		return false, "ACTIVE_CHARACTER_REQUIRED"
	end
	if
		not recipientSession
		or recipientSession.ActiveCharacterId ~= record.Recipient.CharacterId
		or not recipientSession.Profile.Characters[record.Recipient.CharacterId]
	then
		return false, "PHONE_RECIPIENT_UNAVAILABLE"
	end
	local senderCharacter = senderSession.Profile.Characters[record.Sender.CharacterId]
	if record.Amount > senderCharacter.Economy.Balance then
		return false, "INSUFFICIENT_FUNDS"
	end
	return true, nil
end

local function commitRecipient(
	service: any,
	sender: Player,
	recipient: Player,
	expected: any,
	commitAlreadyProven: boolean
): (any?, string?)
	local data = service.context.Services:Get("DataService")
	local rejection: string? = nil
	local updated, reason =
		data:UpdateSharedRecord(Contract.recordKey(expected.Recipient.UserId), function(existing)
			if existing ~= nil then
				if
					not Contract.matches(existing, expected)
					or existing.OwnerSide ~= "Recipient"
				then
					return existing
				end
				if existing.Decision == "Commit" then
					return existing
				end
			end

			if not commitAlreadyProven then
				local allowed, commitReason =
					currentCommitState(service, sender, recipient, expected)
				if not allowed then
					rejection = commitReason
					return existing
				end
			end

			local committed = if existing ~= nil
				then table.clone(existing)
				else Contract.build(expected, "Recipient")
			committed.Decision = "Commit"
			committed.CommitAt = committed.CommitAt or os.time()
			return committed
		end)
	if reason then
		-- UpdateAsync failures are ambiguous. Never delete the sender's prepared
		-- record here: the recipient commit may already be durable.
		return nil, "TRANSFER_SETTLEMENT_PENDING"
	end
	if
		not Contract.matches(updated, expected)
		or updated.OwnerSide ~= "Recipient"
	then
		return nil, "TRANSFER_SETTLEMENT_PENDING"
	end
	if updated.Decision ~= "Commit" then
		return nil, rejection or "TRANSFER_SETTLEMENT_PENDING"
	end
	return updated, nil
end

local function markDurable(
	service: any,
	record: any,
	side: string
): (boolean, string?)
	local party = record[side]
	local key = Contract.recordKey(party.UserId)
	local data = service.context.Services:Get("DataService")
	local conflict = false
	local _, reason = data:UpdateSharedRecord(key, function(existing)
		if existing == nil then
			-- A missing sender is possible after sender-first cleanup. Do not
			-- recreate it; the remaining recipient record can retire itself.
			return nil
		end
		if
			not Contract.matches(existing, record)
			or existing.OwnerSide ~= side
		then
			conflict = true
			return existing
		end
		local durable = table.clone(existing)
		durable.Decision = "Commit"
		durable.Status = "Durable"
		durable.DurableAt = durable.DurableAt or os.time()
		return durable
	end)
	if reason then
		return false, reason
	end
	if conflict then
		return false, "TRANSFER_ID_CONFLICT"
	end
	clearPending(service, party.UserId, record.TransferId)
	return true, nil
end

local function applyAndSaveSide(
	service: any,
	player: Player,
	record: any,
	side: string,
	writeDurable: boolean
): (boolean, string?)
	if not service.running or not playerIsCurrent(player) then
		return false, "TRANSFER_SETTLEMENT_PENDING"
	end
	local data = service.context.Services:Get("DataService")
	local party = record[side]
	local session = data:GetSession(player)
	local character = session
		and session.ActiveCharacterId == party.CharacterId
		and session.Profile.Characters[party.CharacterId]
	if not character then
		return false, "TRANSFER_SETTLEMENT_PENDING"
	end

	local expected = party.Transaction
	local matchingReceipt, receiptExists = transactionState(character, record, side)
	if receiptExists and not matchingReceipt then
		return false, "TRANSFER_ID_CONFLICT"
	end
	if not receiptExists then
		local applied, applyReason = service:Apply(player, {
			TransactionId = expected.TransactionId,
			CharacterId = party.CharacterId,
			Account = "Bank",
			Amount = record.Amount,
			Direction = if side == "Sender" then "Debit" else "Credit",
			ReasonCode = expected.ReasonCode,
			Description = expected.Description,
			RelatedEntityId = record.TransferId,
			Metadata = table.clone(expected.Metadata),
		}, true)
		if not applied then
			if applyReason ~= "DUPLICATE_TRANSACTION" then
				return false, applyReason
			end
			matchingReceipt, receiptExists = transactionState(character, record, side)
			if not receiptExists or not matchingReceipt then
				return false, "TRANSFER_ID_CONFLICT"
			end
		end
	end

	local saved, saveReason = data:Save(player)
	if not saved then
		return false, saveReason or "TRANSFER_SETTLEMENT_PENDING"
	end
	if writeDurable then
		local marked, markReason = markDurable(service, record, side)
		if not marked then
			return false, markReason
		end
	end
	return true, nil
end

local function cleanupAfterDurable(service: any, record: any)
	task.spawn(function()
		if not service.running then
			return
		end
		local senderMarked = markDurable(service, record, "Sender")
		if not senderMarked or not service.running then
			return
		end
		local recipientMarked = markDurable(service, record, "Recipient")
		if not recipientMarked or not service.running then
			return
		end

		-- Sender first is deliberate. If cleanup is interrupted between the two
		-- deletes, the remaining recipient record is already marked Durable and
		-- can infer that sender removal happened only after both profile saves.
		deleteRecord(service, record.Sender.UserId, record.TransferId, false)
		if not service.running then
			return
		end
		deleteRecord(service, record.Recipient.UserId, record.TransferId, false)
	end)
end

local function buildExpected(specification: any): (any, any)
	local senderRecord = Contract.build(specification, "Sender")
	local recipientRecord = Contract.build(specification, "Recipient")
	return senderRecord, recipientRecord
end

function EconomySettlement.execute(
	service: any,
	sender: Player,
	recipient: Player,
	specification: any
): (boolean, string?)
	local senderRecord, recipientRecord = buildExpected(specification)
	setPending(service, senderRecord)

	local data = service.context.Services:Get("DataService")
	local senderSession = data:GetSession(sender)
	local recipientSession = data:GetSession(recipient)
	local senderCharacter = senderSession
		and senderSession.ActiveCharacterId == senderRecord.Sender.CharacterId
		and senderSession.Profile.Characters[senderRecord.Sender.CharacterId]
	local recipientCharacter = recipientSession
		and recipientSession.ActiveCharacterId == senderRecord.Recipient.CharacterId
		and recipientSession.Profile.Characters[senderRecord.Recipient.CharacterId]
	if not senderCharacter or not recipientCharacter then
		return false, "TRANSFER_SETTLEMENT_PENDING"
	end

	local senderReceiptMatches, senderReceiptExists =
		transactionState(senderCharacter, senderRecord, "Sender")
	local recipientReceiptMatches, recipientReceiptExists =
		transactionState(recipientCharacter, senderRecord, "Recipient")
	if
		(senderReceiptExists and not senderReceiptMatches)
		or (recipientReceiptExists and not recipientReceiptMatches)
	then
		return false, "TRANSFER_ID_CONFLICT"
	end
	if senderReceiptExists and recipientReceiptExists then
		clearPending(service, sender.UserId, senderRecord.TransferId)
		clearPending(service, recipient.UserId, senderRecord.TransferId)
		return true, nil
	end

	local senderExisting, senderPrepareReason =
		writePrepared(service, sender.UserId, senderRecord)
	if not senderExisting then
		return false, senderPrepareReason
	end
	local commitAlreadyProven = senderExisting.Decision == "Commit"
		or senderReceiptExists
		or recipientReceiptExists

	local committedRecipient, commitReason =
		commitRecipient(service, sender, recipient, recipientRecord, commitAlreadyProven)
	if not committedRecipient then
		if commitReason ~= "TRANSFER_SETTLEMENT_PENDING" then
			abortPrepared(service, senderRecord)
		end
		return false, commitReason
	end

	-- The recipient record is the durable commit point. From here the transfer
	-- must complete; failures return a pending state rather than compensating a
	-- side that may already have been durably written.
	local senderSaved, senderReason =
		applyAndSaveSide(service, sender, senderRecord, "Sender", false)
	if not senderSaved then
		return false, senderReason or "TRANSFER_SETTLEMENT_PENDING"
	end
	local recipientSaved, recipientReason =
		applyAndSaveSide(service, recipient, recipientRecord, "Recipient", false)
	if not recipientSaved then
		-- Sender is known durable. Persist that proof if possible so recovery can
		-- allow unrelated sender economy work without risking a duplicate debit.
		markDurable(service, senderRecord, "Sender")
		return false, recipientReason or "TRANSFER_SETTLEMENT_PENDING"
	end

	-- Both profile writes are confirmed. The user-facing operation can finish
	-- now; receipt marking and cleanup are recoverable metadata work.
	cleanupAfterDurable(service, senderRecord)
	return true, nil
end

local function ensureCounterpartCommit(service: any, record: any, side: string): boolean
	local counterpart = Contract.counterpart(record, side)
	if not counterpart then
		return false
	end
	local counterpartSide = if side == "Sender" then "Recipient" else "Sender"
	local expected = Contract.build(record, counterpartSide)
	expected.Decision = "Commit"
	local data = service.context.Services:Get("DataService")
	local updated, reason =
		data:UpdateSharedRecord(Contract.recordKey(counterpart.UserId), function(existing)
			if existing == nil then
				return expected
			end
			if
				Contract.matches(existing, expected)
				and existing.OwnerSide == counterpartSide
			then
				local committed = table.clone(existing)
				committed.Decision = "Commit"
				committed.CommitAt = committed.CommitAt or os.time()
				return committed
			end
			return existing
		end)
	return reason == nil
		and Contract.matches(updated, expected)
		and updated.OwnerSide == counterpartSide
		and updated.Decision == "Commit"
end

function EconomySettlement.reconcile(
	service: any,
	player: Player,
	characterId: string,
	transferClaim: any?
): (boolean, string?)
	if not service.running or not playerIsCurrent(player) then
		return false, "ECONOMY_UNAVAILABLE"
	end
	local activeTransfer = service.transferring[player.UserId]
	if activeTransfer and activeTransfer ~= transferClaim then
		return false, "TRANSFER_IN_PROGRESS"
	end
	if service.settlementReconciling[player.UserId] then
		return false, "TRANSFER_SETTLEMENT_IN_PROGRESS"
	end
	local claim = {}
	service.settlementReconciling[player.UserId] = claim

	local ok, result, reason = pcall(function(): (boolean, string?)
		local data = service.context.Services:Get("DataService")
		local record, loadReason = data:GetSharedRecord(Contract.recordKey(player.UserId))
		if loadReason then
			service.settlementPending[player.UserId] = true
			return false, loadReason
		end
		if record == nil then
			service.settlementPending[player.UserId] = nil
			return true, nil
		end
		if not Contract.valid(record) then
			service.settlementPending[player.UserId] = true
			return false, "TRANSFER_SETTLEMENT_INVALID"
		end
		local side = Contract.sideFor(record, player.UserId, characterId)
		if not side then
			service.settlementPending[player.UserId] = record.TransferId
			return false, "TRANSFER_SETTLEMENT_CHARACTER_REQUIRED"
		end
		service.settlementPending[player.UserId] = record.TransferId

		local session = data:GetSession(player)
		local character = session
			and session.ActiveCharacterId == characterId
			and session.Profile.Characters[characterId]
		if not character then
			return false, "CHARACTER_NOT_ACTIVE"
		end
		local receiptMatches, receiptExists = transactionState(character, record, side)
		if receiptExists and not receiptMatches then
			return false, "TRANSFER_ID_CONFLICT"
		end

		local counterpart = Contract.counterpart(record, side)
		if not counterpart then
			return false, "TRANSFER_SETTLEMENT_INVALID"
		end
		local counterpartRecord, counterpartReason =
			data:GetSharedRecord(Contract.recordKey(counterpart.UserId))
		if counterpartReason then
			return false, counterpartReason
		end
		local counterpartMatches = counterpartRecord ~= nil
			and Contract.matches(counterpartRecord, record)
		local commitProven = record.Decision == "Commit"
			or (
				counterpartMatches
				and counterpartRecord.Decision == "Commit"
			)
			or receiptExists

		if not commitProven then
			local aborted = abortPrepared(service, record)
			if not aborted then
				return false, "TRANSFER_SETTLEMENT_PENDING"
			end
			return true, nil
		end

		if side == "Recipient" and record.Status == "Durable" and counterpartRecord == nil then
			-- Cleanup always removes the sender first and only after both sides
			-- were durable. A lone durable recipient is therefore safe to retire.
			deleteRecord(service, player.UserId, record.TransferId, false)
			clearPending(service, player.UserId, record.TransferId)
			return true, nil
		end

		if counterpartRecord == nil and side == "Sender" then
			if not ensureCounterpartCommit(service, record, side) then
				return false, "TRANSFER_SETTLEMENT_PENDING"
			end
			counterpartRecord = Contract.build(record, "Recipient")
			counterpartRecord.Decision = "Commit"
			counterpartMatches = true
		end

		if record.Status ~= "Durable" then
			local settled, settleReason =
				applyAndSaveSide(service, player, record, side, true)
			if not settled then
				return false, settleReason or "TRANSFER_SETTLEMENT_PENDING"
			end
			record.Status = "Durable"
			record.Decision = "Commit"
		else
			clearPending(service, player.UserId, record.TransferId)
		end

		-- Refresh after our durable marker so cleanup decisions are based on the
		-- shared record rather than the snapshot read before the save.
		counterpartRecord, counterpartReason =
			data:GetSharedRecord(Contract.recordKey(counterpart.UserId))
		if counterpartReason then
			return true, nil
		end
		counterpartMatches = counterpartRecord ~= nil
			and Contract.matches(counterpartRecord, record)
		if counterpartMatches and counterpartRecord.Status == "Durable" then
			deleteRecord(service, record.Sender.UserId, record.TransferId, false)
			deleteRecord(service, record.Recipient.UserId, record.TransferId, false)
		elseif counterpartRecord == nil and side == "Recipient" then
			deleteRecord(service, player.UserId, record.TransferId, false)
		end
		return true, nil
	end)

	if service.settlementReconciling[player.UserId] == claim then
		service.settlementReconciling[player.UserId] = nil
	end
	if not ok then
		service.settlementPending[player.UserId] = true
		service.context.Logger:Error("Transfer settlement reconciliation failed", {
			UserId = player.UserId,
			CharacterId = characterId,
			Error = tostring(result),
		})
		return false, "TRANSFER_SETTLEMENT_FAILED"
	end
	return result, reason
end

return EconomySettlement
