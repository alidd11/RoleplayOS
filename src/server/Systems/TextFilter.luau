--!strict

-- Central bound for Roblox text filtering.
--
-- Filtering is a web call that can yield indefinitely. pcall does not help:
-- it traps errors, not stalled yields, so a filtered remote handler would never
-- return and the request would have no response and no error. Every filtered
-- path therefore runs the call in its own coroutine against a deadline.
--
-- Studio commonly has no API access, which is also why the framework mocks
-- DataStores there, so development builds return the raw text immediately.
-- Live servers always filter: the bypass is gated on RunService:IsStudio.

local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local TextFilter = {}

local TIMEOUT_SECONDS = 8
local POLL_SECONDS = 0.05

local function run(
	text: string,
	userId: number,
	context: Enum.TextFilterContext?,
	extract: (any) -> string?
): (string?, string?)
	if type(text) ~= "string" or #text < 1 then
		return nil, "TEXT_FILTER_INVALID_INPUT"
	end
	if RunService:IsStudio() then
		return text, nil
	end
	local finished = false
	local filtered: string? = nil
	task.spawn(function()
		local ok, result = pcall(function()
			if context then
				return TextService:FilterStringAsync(text, userId, context)
			end
			return TextService:FilterStringAsync(text, userId)
		end)
		if ok and result then
			local extracted = extract(result)
			if type(extracted) == "string" and #extracted > 0 then
				filtered = extracted
			end
		end
		finished = true
	end)
	local deadline = os.clock() + TIMEOUT_SECONDS
	while not finished and os.clock() < deadline do
		task.wait(POLL_SECONDS)
	end
	if filtered then
		return filtered, nil
	end
	return nil, if finished then "TEXT_FILTER_UNAVAILABLE" else "TEXT_FILTER_TIMEOUT"
end

-- Text shown to everyone. Callers must treat nil as a refusal, never as
-- permission to broadcast the raw text.
function TextFilter.forBroadcast(
	text: string,
	userId: number,
	context: Enum.TextFilterContext?
): (string?, string?)
	return run(text, userId, context, function(result)
		local ok, value = pcall(result.GetNonChatStringForBroadcastAsync, result)
		return if ok then value else nil
	end)
end

-- Text shown to one recipient, filtered against that recipient.
function TextFilter.forUser(
	text: string,
	fromUserId: number,
	toUserId: number,
	context: Enum.TextFilterContext?
): (string?, string?)
	return run(text, fromUserId, context, function(result)
		local ok, value = pcall(result.GetChatForUserAsync, result, toUserId)
		return if ok then value else nil
	end)
end

return table.freeze(TextFilter)
