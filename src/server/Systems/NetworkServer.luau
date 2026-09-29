--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PayloadInspector = require(ReplicatedStorage.RoleplayOS.Shared.PayloadInspector)
local ResponseInspector = require(ReplicatedStorage.RoleplayOS.Shared.ResponseInspector)
local RateLimiter = require(ReplicatedStorage.RoleplayOS.Shared.RateLimiter)

local NetworkServer = {}
NetworkServer.__index = NetworkServer

local MAXIMUM_RESPONSE_CODE_BYTES = 64
local MAXIMUM_RESPONSE_MESSAGE_BYTES = 512

local function responseCodeIsSafe(value: any): boolean
	return type(value) == "string"
		and #value > 0
		and #value <= MAXIMUM_RESPONSE_CODE_BYTES
		and string.match(value, "^[A-Z][A-Z0-9_]*$") ~= nil
end

local function responseEnvelope(result: any, requestId: string, config: any): (any?, string?)
	if type(result) ~= "table" then
		return nil, "INVALID_RESPONSE_TYPE"
	end
	if type(result.Success) ~= "boolean" then
		return nil, "INVALID_SUCCESS_TYPE"
	end
	if not responseCodeIsSafe(result.Code) then
		return nil, "INVALID_RESPONSE_CODE"
	end
	if type(result.Message) ~= "string" then
		return nil, "INVALID_MESSAGE_TYPE"
	end
	if #result.Message > MAXIMUM_RESPONSE_MESSAGE_BYTES then
		return nil, "RESPONSE_MESSAGE_TOO_LARGE"
	end
	local dataSafe, dataReason = ResponseInspector.validate(result.Data, config)
	if not dataSafe then
		return nil, "INVALID_RESPONSE_DATA:" .. tostring(dataReason)
	end

	-- Build the wire envelope from the declared fields rather than cloning the
	-- handler result. A stray internal field must never become client-visible
	-- merely because a handler included it alongside the supported contract.
	return {
		Success = result.Success,
		Code = result.Code,
		Message = result.Message,
		Data = result.Data,
		RequestId = requestId,
	},
		nil
end

local function releaseActiveSlot(self: any, requestId: string, slot: any): boolean
	if slot.Counted ~= true then
		return false
	end
	slot.Counted = false
	local inFlight = slot.InFlight
	if type(inFlight) == "table" and inFlight[requestId] == slot then
		inFlight[requestId] = nil
	end
	if self.activeSlots[requestId] == slot then
		self.activeSlots[requestId] = nil
	end
	self.activeTotal = math.max(0, self.activeTotal - 1)
	return true
end

function NetworkServer.new(config: any, logger: any)
	local folder = ReplicatedStorage.RoleplayOS.Network:FindFirstChild("Remotes")
		or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage.RoleplayOS.Network
	-- Studio can retain runtime-created instances in the edit DataModel after a
	-- stopped test or an installer save. Reusing that folder without clearing it
	-- creates two children with the same endpoint name. FindFirstChild may then
	-- hand the client the old RemoteFunction, which has no OnServerInvoke in the
	-- new server and therefore yields forever. The server owns this folder, so a
	-- fresh server always starts with a fresh endpoint set.
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
	folder:SetAttribute("Ready", false)
	local self = setmetatable({
		folder = folder,
		config = config,
		logger = logger,
		endpoints = {},
		limiters = {},
		counts = {},
		active = {},
		activeSlots = {},
		activeTotal = 0,
		accepting = true,
		authorizer = nil,
		globalLimiter = RateLimiter.new(
			config.GlobalCapacity or 30,
			config.GlobalRefillPerSecond or 10
		),
	}, NetworkServer)
	self.playerRemoving = Players.PlayerRemoving:Connect(function(player)
		local key = tostring(player.UserId)
		self.globalLimiter:Remove(key)
		for _, limiter in self.limiters do
			limiter:Remove(key)
		end
		self.active[player.UserId] = nil
	end)
	return self
end

-- Installs the server-entry gate used by every RemoteFunction. This lives at
-- the transport boundary so a newly joined player cannot call a less obvious
-- endpoint while an asynchronous group-membership check is still running.
function NetworkServer:SetAuthorizer(authorizer: (Player) -> boolean)
	self.authorizer = authorizer
end

-- Counts outcomes by code.
--
-- Every refusal above is a decision this server made about a request, and
-- until now each one was either silent or a single security log line with no
-- sense of rate. A server refusing one request an hour and a server refusing
-- half of them look identical in a log and completely different to play on.
function NetworkServer:_count(code: string)
	self.counts[code] = (self.counts[code] or 0) + 1
end

-- The counts since the last call, and then resets them.
--
-- Read as a rate rather than a total: a running total only ever grows, so it
-- says how bad the server has ever been rather than how it is now.
function NetworkServer:DrainCounts(): { [string]: number }
	local drained = self.counts
	self.counts = {}
	return drained
end

function NetworkServer:RegisterFunction(
	name: string,
	schema: (any) -> (boolean, string?),
	handler: (Player, any, string) -> any
)
	assert(self.endpoints[name] == nil, "Duplicate endpoint: " .. name)
	local stale = self.folder:FindFirstChild(name)
	if stale then
		stale:Destroy()
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = self.folder
	local limits = self.config.Endpoints[name]
	assert(limits ~= nil, "Explicit rate limit required for endpoint: " .. name)
	local limiter = RateLimiter.new(limits.Capacity, limits.RefillPerSecond)
	self.limiters[name] = limiter
	self.endpoints[name] = remote
	remote.OnServerInvoke = function(player: Player, payload: any)
		local requestId = HttpService:GenerateGUID(false)
		if not self.accepting then
			self:_count("SERVER_SHUTTING_DOWN")
			return {
				Success = false,
				Code = "SERVER_SHUTTING_DOWN",
				Message = "This server is closing. Please rejoin.",
				RequestId = requestId,
			}
		end
		local userKey = tostring(player.UserId)
		if not self.globalLimiter:Allow(userKey) or not limiter:Allow(userKey) then
			self:_count("RATE_LIMITED")
			return {
				Success = false,
				Code = "RATE_LIMITED",
				Message = "Please wait before trying again.",
				RequestId = requestId,
			}
		end
		if self.authorizer then
			local authorizerOk, authorized = pcall(self.authorizer, player)
			if not authorizerOk or authorized ~= true then
				self:_count("ACCESS_PENDING")
				return {
					Success = false,
					Code = "ACCESS_PENDING",
					Message = "Your server access is still being verified.",
					RequestId = requestId,
				}
			end
		end
		local structurallySafe, structuralReason = PayloadInspector.validate(payload, self.config)
		if not structurallySafe then
			self.logger:Security("Rejected complex remote payload", {
				Endpoint = name,
				UserId = player.UserId,
				Reason = structuralReason,
			})
			self:_count("PAYLOAD_REJECTED")
			return {
				Success = false,
				Code = "PAYLOAD_REJECTED",
				Message = "The request was invalid.",
				RequestId = requestId,
			}
		end
		local encodedOk, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
		if not encodedOk or #encoded > self.config.MaximumPayloadBytes then
			self:_count("PAYLOAD_REJECTED")
			return {
				Success = false,
				Code = "PAYLOAD_REJECTED",
				Message = "The request was too large or invalid.",
				RequestId = requestId,
			}
		end
		local schemaOk, valid, reason = pcall(schema, payload)
		if not schemaOk or not valid then
			self.logger:Security("Rejected remote payload", {
				Endpoint = name,
				UserId = player.UserId,
				Reason = if schemaOk then reason else "SCHEMA_ERROR",
			})
			self:_count("INVALID_REQUEST")
			return {
				Success = false,
				Code = "INVALID_REQUEST",
				Message = "The request was invalid.",
				RequestId = requestId,
			}
		end
		-- In-flight requests are counted until the handler finishes or its slot
		-- reaches the configured abandonment ceiling. Each slot owns an independent
		-- timer so a request that stalls after its player leaves cannot disappear
		-- from the per-player table while permanently occupying the server-wide
		-- concurrency budget.
		local inFlight = self.active[player.UserId]
		if not inFlight then
			inFlight = {}
			self.active[player.UserId] = inFlight
		end
		local now = os.clock()
		local ceiling = self.config.RequestAbandonSeconds or 30
		local active = 0
		for _, slot in inFlight do
			if slot.Counted == true then
				active += 1
			end
		end
		if active >= (self.config.MaximumConcurrentRequests or 4) then
			self:_count("SERVER_BUSY")
			return {
				Success = false,
				Code = "SERVER_BUSY",
				Message = "Please wait before trying again.",
				RequestId = requestId,
			}
		end
		if self.activeTotal >= (self.config.MaximumConcurrentRequestsPerServer or 64) then
			self:_count("SERVER_BUSY")
			return {
				Success = false,
				Code = "SERVER_BUSY",
				Message = "The server is busy. Please try again shortly.",
				RequestId = requestId,
			}
		end
		-- Re-check immediately before acquiring the active slot. A request can
		-- pass the first gate just before shutdown begins, then spend time in
		-- authorisation/schema validation. There is no yield between this check
		-- and the counter increment, so BeginShutdown cannot miss a handler that
		-- is about to start while deciding whether the transport is idle.
		if not self.accepting then
			self:_count("SERVER_SHUTTING_DOWN")
			return {
				Success = false,
				Code = "SERVER_SHUTTING_DOWN",
				Message = "This server is closing. Please rejoin.",
				RequestId = requestId,
			}
		end
		local slot = {
			StartedAt = now,
			Counted = true,
			InFlight = inFlight,
			Endpoint = name,
			UserId = player.UserId,
		}
		inFlight[requestId] = slot
		self.activeSlots[requestId] = slot
		self.activeTotal += 1
		task.delay(ceiling, function()
			if releaseActiveSlot(self, requestId, slot) then
				self.logger:Warning("Abandoned a stuck request slot", {
					Endpoint = slot.Endpoint,
					UserId = slot.UserId,
					HeldSeconds = math.floor(os.clock() - slot.StartedAt),
				})
			end
		end)

		-- The handler runs alongside a deadline rather than being waited on.
		--
		-- OnServerInvoke returns when the handler does, and InvokeServer yields
		-- the caller until it does, so a handler that stalls leaves the player
		-- staring at a button that never comes back. Every long wait reported in
		-- this game has been that: a web call, a data store, a filter, and an
		-- interface with no way to know it was never going to hear back.
		--
		-- A client side timeout only decides how long the player stares. The
		-- server answering is what stops it happening, so it always answers, and
		-- a handler that is still running is left to finish into nothing.
		--
		-- The slot is deliberately not released on a timeout: that handler is
		-- still holding whatever it was holding, and the reclaim above frees it
		-- once it is genuinely presumed lost.
		local finished, ok, result = false, false, nil
		task.spawn(function()
			local handlerOk, handlerResult = pcall(handler, player, payload, requestId)
			ok, result = handlerOk, handlerResult
			-- A caller may already have received SERVER_TIMEOUT by the time the
			-- handler finishes. Release exactly once: the abandonment timer may
			-- already have reclaimed this slot.
			releaseActiveSlot(self, requestId, slot)
			finished = true
		end)
		local handlerDeadline = os.clock() + (self.config.HandlerTimeoutSeconds or 8)
		while not finished and os.clock() < handlerDeadline do
			task.wait(0.03)
		end
		if not finished then
			self.logger:Error("Remote handler did not answer in time", {
				Endpoint = name,
				RequestId = requestId,
				UserId = player.UserId,
				Seconds = self.config.HandlerTimeoutSeconds or 8,
			})
			self:_count("SERVER_TIMEOUT")
			return {
				Success = false,
				Code = "SERVER_TIMEOUT",
				Message = "That is taking longer than it should. Try again.",
				RequestId = requestId,
			}
		end
		inFlight[requestId] = nil
		if not ok then
			self.logger:Error("Remote handler failed", {
				Endpoint = name,
				RequestId = requestId,
				Error = tostring(result),
			})
			self:_count("SERVER_ERROR")
			return {
				Success = false,
				Code = "SERVER_ERROR",
				Message = "The request could not be completed.",
				RequestId = requestId,
			}
		end
		local envelope, envelopeReason = responseEnvelope(result, requestId, self.config)
		if not envelope then
			self.logger:Error("Remote handler returned an unsafe response envelope", {
				Endpoint = name,
				RequestId = requestId,
				Reason = envelopeReason,
			})
			self:_count("SERVER_ERROR")
			return {
				Success = false,
				Code = "SERVER_ERROR",
				Message = "The request could not be completed.",
				RequestId = requestId,
			}
		end
		return envelope
	end
end

-- Published once every endpoint is registered so clients can distinguish "the
-- server is still starting" from "this endpoint genuinely does not exist".
function NetworkServer:MarkReady()
	self.folder:SetAttribute("Ready", true)
end

function NetworkServer:BeginShutdown()
	self.accepting = false
	self.folder:SetAttribute("Ready", false)
end

function NetworkServer:DrainActive(timeoutSeconds: number): (boolean, number)
	local deadline = os.clock() + math.max(0, timeoutSeconds)
	while self.activeTotal > 0 and os.clock() < deadline do
		task.wait(0.03)
	end
	return self.activeTotal == 0, self.activeTotal
end

function NetworkServer:Destroy()
	self:BeginShutdown()
	if self.playerRemoving then
		self.playerRemoving:Disconnect()
	end
	for _, limiter in self.limiters do
		for _, player in Players:GetPlayers() do
			limiter:Remove(tostring(player.UserId))
		end
	end
	for _, player in Players:GetPlayers() do
		self.globalLimiter:Remove(tostring(player.UserId))
	end
	-- Prevent delayed abandonment/completion callbacks from adjusting counters or
	-- emitting warnings after teardown. The callbacks retain only slot tables,
	-- not Player instances.
	for _, slot in self.activeSlots do
		slot.Counted = false
	end
	table.clear(self.activeSlots)
	table.clear(self.active)
	self.activeTotal = 0
end

function NetworkServer:RegisterEvent(name: string): RemoteEvent
	assert(self.endpoints[name] == nil, "Duplicate endpoint: " .. name)
	local stale = self.folder:FindFirstChild(name)
	if stale then
		stale:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = self.folder
	self.endpoints[name] = remote
	return remote
end

return NetworkServer
