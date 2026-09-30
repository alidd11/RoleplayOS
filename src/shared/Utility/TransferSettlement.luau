--!strict

local TransferSettlement = {}

local MAXIMUM_OPERATION_ID_BYTES = 64
local MAXIMUM_TRANSFER_ID_BYTES = 160

local function boundedString(value: any, minimum: number, maximum: number): boolean
	return type(value) == "string" and #value >= minimum and #value <= maximum
end

local function validParty(party: any): boolean
	return type(party) == "table"
		and type(party.UserId) == "number"
		and party.UserId > 0
		and party.UserId == math.floor(party.UserId)
		and boundedString(party.CharacterId, 1, 64)
		and type(party.Transaction) == "table"
		and boundedString(party.Transaction.TransactionId, 1, 220)
		and boundedString(party.Transaction.ReasonCode, 1, 80)
		and type(party.Transaction.Description) == "string"
		and #party.Transaction.Description <= 160
		and type(party.Transaction.Metadata) == "table"
end

function TransferSettlement.operationId(value: any): string?
	if
		not boundedString(value, 1, MAXIMUM_OPERATION_ID_BYTES)
		or string.match(value, "^[%w%-%_:]+$") == nil
	then
		return nil
	end
	return value
end

function TransferSettlement.recordKey(userId: number): string
	return "ts:" .. tostring(userId)
end

function TransferSettlement.transferId(
	kind: string,
	senderCharacterId: string,
	operationId: string
): string
	local namespace = if kind == "TaxiFare" then "taxi" else "player"
	return namespace .. ":" .. senderCharacterId .. ":" .. operationId
end

function TransferSettlement.transactionId(transferId: string, side: string): string
	local suffix = if side == "Sender" then "debit" else "credit"
	return "settlement:" .. suffix .. ":" .. transferId
end

function TransferSettlement.build(specification: any, side: string): any
	assert(side == "Sender" or side == "Recipient", "invalid settlement side")
	local record = {
		Version = 1,
		TransferId = specification.TransferId,
		Kind = specification.Kind,
		Amount = specification.Amount,
		CreatedAt = specification.CreatedAt,
		Decision = specification.Decision or "Prepared",
		OwnerSide = side,
		Status = specification.Status or "Prepared",
		Sender = {
			UserId = specification.Sender.UserId,
			CharacterId = specification.Sender.CharacterId,
			Transaction = table.clone(specification.Sender.Transaction),
		},
		Recipient = {
			UserId = specification.Recipient.UserId,
			CharacterId = specification.Recipient.CharacterId,
			Transaction = table.clone(specification.Recipient.Transaction),
		},
	}
	record.Sender.Transaction.Metadata =
		table.clone(specification.Sender.Transaction.Metadata or {})
	record.Recipient.Transaction.Metadata =
		table.clone(specification.Recipient.Transaction.Metadata or {})
	return record
end

function TransferSettlement.valid(record: any): boolean
	if
		type(record) ~= "table"
		or record.Version ~= 1
		or not boundedString(record.TransferId, 1, MAXIMUM_TRANSFER_ID_BYTES)
		or not boundedString(record.Kind, 1, 32)
		or type(record.Amount) ~= "number"
		or record.Amount <= 0
		or record.Amount ~= math.floor(record.Amount)
		or type(record.CreatedAt) ~= "number"
		or record.CreatedAt <= 0
		or (record.Decision ~= "Prepared" and record.Decision ~= "Commit")
		or (record.OwnerSide ~= "Sender" and record.OwnerSide ~= "Recipient")
		or (record.Status ~= "Prepared" and record.Status ~= "Durable")
		or not validParty(record.Sender)
		or not validParty(record.Recipient)
	then
		return false
	end
	if record.Sender.UserId == record.Recipient.UserId then
		return false
	end
	if
		record.Sender.Transaction.TransactionId
			~= TransferSettlement.transactionId(record.TransferId, "Sender")
		or record.Recipient.Transaction.TransactionId
			~= TransferSettlement.transactionId(record.TransferId, "Recipient")
	then
		return false
	end
	return true
end

function TransferSettlement.sideFor(
	record: any,
	userId: number,
	characterId: string
): string?
	if not TransferSettlement.valid(record) then
		return nil
	end
	if record.Sender.UserId == userId and record.Sender.CharacterId == characterId then
		return "Sender"
	end
	if record.Recipient.UserId == userId and record.Recipient.CharacterId == characterId then
		return "Recipient"
	end
	return nil
end

function TransferSettlement.counterpart(record: any, side: string): any?
	if not TransferSettlement.valid(record) then
		return nil
	end
	if side == "Sender" then
		return record.Recipient
	end
	if side == "Recipient" then
		return record.Sender
	end
	return nil
end

function TransferSettlement.matches(existing: any, expected: any): boolean
	return TransferSettlement.valid(existing)
		and TransferSettlement.valid(expected)
		and existing.TransferId == expected.TransferId
		and existing.Kind == expected.Kind
		and existing.Amount == expected.Amount
		and existing.Sender.UserId == expected.Sender.UserId
		and existing.Sender.CharacterId == expected.Sender.CharacterId
		and existing.Recipient.UserId == expected.Recipient.UserId
		and existing.Recipient.CharacterId == expected.Recipient.CharacterId
		and existing.Sender.Transaction.ReasonCode == expected.Sender.Transaction.ReasonCode
		and existing.Recipient.Transaction.ReasonCode == expected.Recipient.Transaction.ReasonCode
end

return table.freeze(TransferSettlement)
