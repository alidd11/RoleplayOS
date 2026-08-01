--!strict

local EconomyValidator = {}

function EconomyValidator.amount(amount: any): (boolean, string?)
	if type(amount) ~= "number" then
		return false, "AMOUNT_TYPE"
	end
	if amount ~= amount or math.abs(amount) == math.huge then
		return false, "AMOUNT_NOT_FINITE"
	end
	if amount <= 0 then
		return false, "AMOUNT_NOT_POSITIVE"
	end
	if amount % 1 ~= 0 then
		return false, "AMOUNT_NOT_INTEGER"
	end
	return true, nil
end

function EconomyValidator.transaction(
	transaction: any,
	seen: { [string]: boolean },
	balance: number
): (boolean, string?)
	if
		type(transaction) ~= "table"
		or type(transaction.TransactionId) ~= "string"
		or transaction.TransactionId == ""
	then
		return false, "INVALID_TRANSACTION"
	end
	if seen[transaction.TransactionId] then
		return false, "DUPLICATE_TRANSACTION"
	end
	local valid, reason = EconomyValidator.amount(transaction.Amount)
	if not valid then
		return false, reason
	end
	if transaction.Direction ~= "Credit" and transaction.Direction ~= "Debit" then
		return false, "INVALID_DIRECTION"
	end
	if transaction.Direction == "Debit" and transaction.Amount > balance then
		return false, "INSUFFICIENT_FUNDS"
	end
	return true, nil
end

return table.freeze(EconomyValidator)
