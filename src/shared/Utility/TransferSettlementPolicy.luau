--!strict

local TransferSettlementPolicy = {}

function TransferSettlementPolicy.transactionId(transferId: string, side: string): string
	return "settlement:" .. transferId .. ":" .. side
end

function TransferSettlementPolicy.acknowledge(
	status: string,
	senderSaved: boolean,
	recipientSaved: boolean,
	side: "Sender" | "Recipient"
): (string?, boolean?, boolean?)
	if status ~= "Committed" then
		return nil, nil, nil
	end
	if side == "Sender" then
		senderSaved = true
	else
		recipientSaved = true
	end
	return if senderSaved and recipientSaved then "Settled" else "Committed",
		senderSaved,
		recipientSaved
end

function TransferSettlementPolicy.receiptMatches(
	receipt: any,
	transferId: string,
	senderCharacterId: string,
	recipientUserId: number,
	recipientCharacterId: string,
	amount: number,
	kind: string
): boolean
	return type(receipt) == "table"
		and receipt.TransferId == transferId
		and receipt.SenderCharacterId == senderCharacterId
		and receipt.RecipientUserId == recipientUserId
		and receipt.RecipientCharacterId == recipientCharacterId
		and receipt.Amount == amount
		and receipt.Kind == kind
end

return table.freeze(TransferSettlementPolicy)
