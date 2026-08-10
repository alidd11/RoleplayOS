--!strict

-- Turns a burst of "something changed" notifications into one refresh.
--
-- Every dispatch change is broadcast to every client, and a client may hold
-- several panels that all want to redraw when it arrives. During an incident
-- those changes arrive in bursts: a call is created, three units are assigned,
-- each of them reports a status. Answering every one of them separately means a
-- panel sends the server a handful of requests inside a second to draw the same
-- picture it would have drawn from the last of them alone.
--
-- The server's rate limits are the reason this matters rather than merely being
-- wasteful. A bucket emptied by automatic refreshes is empty for the officer
-- too, so the panel stops updating and their own next action is refused, in the
-- middle of the exact incident the panel exists for.
--
-- Trailing edge, deliberately. The first change is answered at once so the
-- display stays live, and everything arriving during the interval collapses
-- into a single refresh at the end of it. Leading-edge-only would drop the last
-- change of a burst, which is the one that matters: it leaves the panel showing
-- a state that is no longer true and nothing further arrives to correct it.
local Coalescer = {}
Coalescer.__index = Coalescer

export type Coalescer = {
	Request: (self: Coalescer) -> (),
	Cancel: (self: Coalescer) -> (),
}

-- `interval` is the shortest gap allowed between two runs. Match it to the
-- refill rate of whatever endpoint the callback calls, leaving room for the
-- player's own actions, which share the same bucket.
function Coalescer.new(interval: number, run: () -> ()): Coalescer
	return (
		setmetatable({
			interval = math.max(interval, 0),
			run = run,
			-- Far enough in the past that the first request runs immediately.
			lastAt = -math.huge,
			pending = false,
			scheduled = false,
			running = false,
			cancelled = false,
		}, Coalescer) :: any
	) :: Coalescer
end

function Coalescer:Request()
	self.pending = true
	-- A run in progress picks the request up when it finishes, and one already
	-- scheduled is the run this request was going to ask for.
	if self.cancelled or self.running or self.scheduled then
		return
	end
	self:_schedule()
end

function Coalescer:_schedule()
	local remaining = self.interval - (os.clock() - self.lastAt)
	if remaining <= 0 then
		self:_run()
		return
	end
	self.scheduled = true
	task.delay(remaining, function()
		self.scheduled = false
		if self.cancelled or not self.pending then
			return
		end
		self:_run()
	end)
end

function Coalescer:_run()
	if self.cancelled then
		return
	end
	-- Cleared before the call rather than after it, so a change that arrives
	-- while the request is in flight schedules another run instead of being
	-- swallowed by the one that was already reading older state.
	self.pending = false
	self.running = true
	local ok, err = pcall(self.run)
	self.running = false
	-- Measured from when the work finished, not when it started. The requests
	-- these callbacks make yield, and timing from the start would let a slow
	-- server produce exactly the overlapping burst this exists to prevent.
	self.lastAt = os.clock()
	if not ok then
		-- Reported rather than raised. This runs inside a scheduler callback with
		-- no caller to catch it, and a refresh that fails must not stop the panel
		-- refreshing again later.
		warn("Coalesced refresh failed: " .. tostring(err))
	end
	if self.pending and not self.cancelled then
		self:_schedule()
	end
end

-- Stops a trailing run that has been scheduled but not yet happened. Controllers
-- call this when they are destroyed, so a refresh cannot fire against torn-down
-- interface a second after the player put it away.
function Coalescer:Cancel()
	self.cancelled = true
	self.pending = false
end

return Coalescer
