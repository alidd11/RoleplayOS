--!strict

-- Roblox text filtering is a web call. It can yield indefinitely when the
-- experience has no API access, which pcall cannot protect against: pcall traps
-- errors, not stalled yields. Every filtered request would then hang forever
-- with no response and no error, so all filtering goes through this bound.

local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local TextFilter = {}

local TIMEOUT_SECONDS = 8
local POLL_SECONDS = 0.05

-- Returns the filtered string, or nil with a reason when filtering could not be
-- completed. Callers must treat nil as a refusal, never as permission to
-- broadcast the raw text.
function TextFilter.filter(text: string, userId: number): (string?, string?)
	if type(text) ~= "string" or #text < 1 then
		return nil, "TEXT_FILTER_INVALID_INPUT"
	end
	local finished = false
	local filtered: string? = nil
	task.spawn(function()
		local ok, result = pcall(function()
			return TextService:FilterStringAsync(text, userId):GetNonChatStringForBroadcastAsync()
		end)
		if ok and type(result) == "string" and #result > 0 then
			filtered = result
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
	-- Studio commonly has no API access, which is also why the framework mocks
	-- DataStores there. Without this the whole experience is untestable locally,
	-- so development builds fall back to the raw text. Live servers never do.
	if RunService:IsStudio() then
		return text, nil
	end
	return nil, if finished then "TEXT_FILTER_UNAVAILABLE" else "TEXT_FILTER_TIMEOUT"
end

return table.freeze(TextFilter)
