--!strict

local MoneyDropPolicy = {}

function MoneyDropPolicy.validateAmount(
	amount: any,
	minimum: number,
	maximum: number
): (boolean, string?)
	if
		type(amount) ~= "number"
		or amount ~= amount
		or amount == math.huge
		or amount == -math.huge
	then
		return false, "INVALID_AMOUNT"
	end
	if amount % 1 ~= 0 then
		return false, "WHOLE_AMOUNT_REQUIRED"
	end
	if amount < minimum then
		return false, "DROP_TOO_SMALL"
	end
	if amount > maximum then
		return false, "DROP_TOO_LARGE"
	end
	return true, nil
end

return MoneyDropPolicy
