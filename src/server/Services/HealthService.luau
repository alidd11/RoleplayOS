--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

-- What the server is actually doing, on a timer.
--
-- Everything wrong with this game so far has been reported as a feeling: it is
-- looping, it is laggy, people are getting kicked. Each of those turned out to
-- have a specific cause, and each took far longer to find than it should have
-- because there was no record of what the server looked like at the time.
--
-- This does not fix anything. It means the next problem arrives with evidence
-- attached, and it means a server heading for trouble says so before the
-- players notice rather than after.
local HealthService = { running = false }

-- Anything past these is worth saying out loud. They are deliberately not
-- tight: a warning that fires on a healthy server teaches everyone to ignore
-- warnings, which is worse than not having them.
local HEARTBEAT_WARNING_MS = 40
local PHYSICS_WARNING_FPS = 40
local MEMORY_WARNING_MB = 2500
local DATASTORE_BUDGET_WARNING = 10

function HealthService:Init(context: any)
	self.context = context
end

function HealthService:_sample(): any
	local budget =
		DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	-- No instance count here on purpose. Walking every descendant of the data
	-- model is the one genuinely expensive thing this could sample, and a health
	-- monitor that costs a frame every minute is causing the problem it exists to
	-- report. Memory is the cheap proxy for the same leak.
	return {
		Players = #Players:GetPlayers(),
		MemoryMb = math.floor(Stats:GetTotalMemoryUsageMb()),
		HeartbeatMs = math.floor(Stats.HeartbeatTimeMs * 100) / 100,
		PhysicsFps = math.floor(workspace:GetRealPhysicsFPS()),
		DataStoreBudget = budget,
	}
end

-- Turns a sample into the reasons it is unhealthy, or an empty list.
local function concerns(sample: any): { string }
	local found = {}
	if sample.HeartbeatMs > HEARTBEAT_WARNING_MS then
		-- The server is taking longer than this to complete a step, so every
		-- player is feeling it as delay, not just the one doing something.
		table.insert(found, "slow heartbeat")
	end
	if sample.PhysicsFps < PHYSICS_WARNING_FPS then
		table.insert(found, "physics behind")
	end
	if sample.MemoryMb > MEMORY_WARNING_MB then
		table.insert(found, "memory high")
	end
	if sample.DataStoreBudget < DATASTORE_BUDGET_WARNING then
		-- The one that costs players their progress rather than their patience.
		table.insert(found, "datastore budget low")
	end
	return found
end

function HealthService:Start()
	local settings = self.context.Configuration.Health
	if not settings.Enabled or not RunService:IsRunning() then
		return
	end
	self.running = true
	task.spawn(function()
		-- Offset from startup so the first sample is of a running server rather
		-- than of one still starting, which is always its worst minute.
		task.wait(settings.FirstSampleSeconds)
		while self.running do
			-- Guarded for the reason WorldBudgetService documents: an engine read
			-- that throws kills the spawned thread, and this thread is the only
			-- reader of Registry:Failed, so the one mechanism that reports a
			-- stepped-over service would stop with nothing to show for it.
			local sampled, sample = pcall(function()
				return self:_sample()
			end)
			if not sampled then
				self.context.Logger:Warning("Could not sample server health", {
					Error = tostring(sample),
				})
				task.wait(settings.IntervalSeconds)
				continue
			end
			-- Refusals are drained rather than totalled, so this reads as a rate
			-- over the interval. A running total only says how bad the server has
			-- ever been, never how it is now.
			sample.Refusals = self.context.Network:DrainCounts()
			local problems = concerns(sample)
			-- A server can now run with a service missing rather than refusing to
			-- run at all, which is the right trade but only if the missing service
			-- is visible. Otherwise it is discovered by a player standing in a
			-- dealership that does nothing.
			local failed = self.context.Services:Failed()
			if #failed > 0 then
				sample.FailedServices = table.concat(failed, ", ")
				table.insert(problems, "services degraded")
			end
			if #problems > 0 then
				sample.Concerns = table.concat(problems, ", ")
				self.context.Logger:Warning("Server health", sample)
			else
				self.context.Logger:Info("Server health", sample)
			end
			self.latest = sample
			task.wait(settings.IntervalSeconds)
		end
	end)
end

-- The most recent sample, for anything that wants to show it.
function HealthService:Latest(): any?
	return self.latest
end

function HealthService:Destroy()
	self.running = false
end

return HealthService
