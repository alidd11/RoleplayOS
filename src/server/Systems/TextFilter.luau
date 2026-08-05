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

-- Long enough for a filter that is working, short enough that a handler waiting
-- on one still answers. Eight seconds was neither: two fields filtered one after
-- the other could not finish inside any sensible request budget, which is why
-- creating a character timed out rather than failing.
local TIMEOUT_SECONDS = 4
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

-- Filters several strings at once.
--
-- Filtering is a web call, so doing them one after another costs the sum of
-- their waits: two fields at up to four seconds each is eight, which no request
-- should spend. Run together they cost the slowest one.
--
-- Returns nil and the first refusal, since a caller that cannot show one field
-- has nothing to do with the rest.
function TextFilter.manyForBroadcast(
	texts: { [string]: string },
	userId: number,
	context: Enum.TextFilterContext?
): ({ [string]: string }?, string?)
	local results: { [string]: string } = {}
	local failure: string? = nil
	local pending = 0
	for key, text in texts do
		pending += 1
		task.spawn(function()
			local value, reason = TextFilter.forBroadcast(text, userId, context)
			if value then
				results[key] = value
			else
				failure = failure or reason or "TEXT_FILTER_UNAVAILABLE"
			end
			pending -= 1
		end)
	end
	-- Bounded by the same deadline the individual calls use, so a spawned filter
	-- that never returns cannot hold this open either.
	local deadline = os.clock() + TIMEOUT_SECONDS + 1
	while pending > 0 and os.clock() < deadline do
		task.wait(POLL_SECONDS)
	end
	if pending > 0 then
		return nil, "TEXT_FILTER_TIMEOUT"
	end
	if failure then
		return nil, failure
	end
	return results, nil
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
	-- GetNonChatStringForUserAsync, not GetChatForUserAsync. Every caller here is
	-- non-chat text -- phone messages, MDT records -- so the chat extractor was
	-- the wrong one on meaning alone, before considering that it is deprecated
	-- and the non-chat pair is not.
	return run(text, fromUserId, context, function(result)
		local ok, value = pcall(result.GetNonChatStringForUserAsync, result, toUserId)
		return if ok then value else nil
	end)
end

return table.freeze(TextFilter)
