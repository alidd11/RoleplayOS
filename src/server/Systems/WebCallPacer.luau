--!strict

-- One queue, for the whole server, in front of Roblox's metered web calls.
--
-- Group membership and gamepass ownership are both metered per server, and both
-- were paced with a per-player wait. Spacing and jitter decorrelate two joiners
-- from each other; they do nothing about the total. Thirty players arriving
-- together each ran their own loop, so the aggregate rate scaled with the number
-- of people joining, which is the only situation that matters.
--
-- On a server filling to thirty after a restart that came to roughly eight
-- hundred metered calls in fifteen seconds, peaking around sixty five a second.
-- Roblox answers that with a 429, this framework read the failure as "could not
-- verify your membership", and the burst kicked the very players it was
-- checking. A server that filled up threw a chunk of its own players out at the
-- door.
--
-- Waiting here reserves the next slot before yielding, so callers are served in
-- the order they arrive and the reservation cannot be taken twice.
--
-- Nothing a player is waiting on goes through this. The link that gates entry is
-- fetched directly, because somebody is standing at the door for it. Everything
-- else is a prefetch and can take as long as it likes: a pass that resolves a
-- minute later is invisible, and a throttled one reads as unowned.
local WebCallPacer = {
	-- Three a second leaves plenty of headroom under Roblox's ceiling and still
	-- finishes a full server's prefetching in a few minutes.
	interval = 1 / 3,
	nextAt = 0,
}

function WebCallPacer:Wait()
	local now = os.clock()
	local at = math.max(now, self.nextAt)
	self.nextAt = at + self.interval
	local delay = at - now
	if delay > 0 then
		task.wait(delay)
	end
end

return WebCallPacer
