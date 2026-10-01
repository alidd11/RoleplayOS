--!strict

local TaxiSettlementPolicy = {}

local definitiveNoSettlementFailures: { [string]: boolean } = {
	INSUFFICIENT_FUNDS = true,
	INVALID_TAXI_FARE = true,
}

-- A completed journey remains outstanding after any ambiguous or recoverable
-- economy failure. Only these responses prove that no fare can be settled.
function TaxiSettlementPolicy.shouldKeepFarePending(success: any, reason: any): boolean
	if success == true then
		return false
	end
	return type(reason) ~= "string" or definitiveNoSettlementFailures[reason] ~= true
end

return table.freeze(TaxiSettlementPolicy)
