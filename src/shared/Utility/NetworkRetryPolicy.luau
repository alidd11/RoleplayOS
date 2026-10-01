--!strict

local NetworkRetryPolicy = {}

-- Only these failures prove that a bank transfer did not commit, or that the
-- current key cannot be used for this request. Unknown and transport/server
-- failures are ambiguous: keep the idempotency key for a safe retry.
local definitiveBankTransferFailures: { [string]: boolean } = {
	ACTIVE_CHARACTER_REQUIRED = true,
	INSUFFICIENT_FUNDS = true,
	INVALID_RECIPIENT_NAME = true,
	INVALID_TRANSFER_ID = true,
	PHONE_RECIPIENT_UNAVAILABLE = true,
	RECIPIENT_NAME_AMBIGUOUS = true,
	SELF_TRANSFER = true,
	TRANSFER_ID_CONFLICT = true,
	TRANSFER_LIMIT = true,
}

function NetworkRetryPolicy.shouldRetainBankTransferId(success: any, code: any): boolean
	if success == true then
		return false
	end
	return type(code) ~= "string" or definitiveBankTransferFailures[code] ~= true
end

function NetworkRetryPolicy.canReusePendingBankTransfer(
	pendingFingerprint: any,
	currentFingerprint: string
): boolean
	return pendingFingerprint == nil or pendingFingerprint == currentFingerprint
end

return table.freeze(NetworkRetryPolicy)
