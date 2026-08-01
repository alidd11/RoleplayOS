--!strict

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: (() -> number)?)
	assert(capacity > 0 and refillPerSecond >= 0, "Invalid token bucket configuration")
	return setmetatable(
		{ capacity = capacity, refill = refillPerSecond, clock = clock or os.clock, buckets = {} },
		RateLimiter
	)
end

function RateLimiter:Allow(key: string, cost: number?): boolean
	local now = self.clock()
	local bucket = self.buckets[key] or { tokens = self.capacity, updated = now }
	bucket.tokens = math.min(self.capacity, bucket.tokens + (now - bucket.updated) * self.refill)
	bucket.updated = now
	local requested = cost or 1
	if requested <= 0 or bucket.tokens < requested then
		self.buckets[key] = bucket
		return false
	end
	bucket.tokens -= requested
	self.buckets[key] = bucket
	return true
end

function RateLimiter:Remove(key: string)
	self.buckets[key] = nil
end

return RateLimiter
