--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PayloadInspector = require(ReplicatedStorage.RoleplayOS.Shared.PayloadInspector)
local RateLimiter = require(ReplicatedStorage.RoleplayOS.Shared.RateLimiter)

local NetworkServer = {}
NetworkServer.__index = NetworkServer

function NetworkServer.new(config: any, logger: any)
	local folder = ReplicatedStorage.RoleplayOS.Network:FindFirstChild("Remotes")
		or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage.RoleplayOS.Network
	local self = setmetatable({
		folder = folder,
		config = config,
		logger = logger,
		endpoints = {},
		limiters = {},
		active = {},
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

function NetworkServer:RegisterFunction(
	name: string,
	schema: (any) -> (boolean, string?),
	handler: (Player, any, string) -> any
)
	assert(self.endpoints[name] == nil, "Duplicate endpoint: " .. name)
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
		local userKey = tostring(player.UserId)
		if not self.globalLimiter:Allow(userKey) or not limiter:Allow(userKey) then
			return {
				Success = false,
				Code = "RATE_LIMITED",
				Message = "Please wait before trying again.",
				RequestId = requestId,
			}
		end
		local structurallySafe, structuralReason = PayloadInspector.validate(payload, self.config)
		if not structurallySafe then
			self.logger:Security("Rejected complex remote payload", {
				Endpoint = name,
				UserId = player.UserId,
				Reason = structuralReason,
			})
			return {
				Success = false,
				Code = "PAYLOAD_REJECTED",
				Message = "The request was invalid.",
				RequestId = requestId,
			}
		end
		local encodedOk, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
		if not encodedOk or #encoded > self.config.MaximumPayloadBytes then
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
			return {
				Success = false,
				Code = "INVALID_REQUEST",
				Message = "The request was invalid.",
				RequestId = requestId,
			}
		end
		-- In-flight requests are tracked individually with a start time rather
		-- than as a count. A handler that yields indefinitely never reaches the
		-- release below, and a bare counter would leak that slot for the rest of
		-- the session: once the limit was reached every later request from this
		-- player was refused, whatever the endpoint. Presuming a long-running
		-- request lost keeps one stuck call from wedging the whole session.
		local inFlight = self.active[player.UserId]
		if not inFlight then
			inFlight = {}
			self.active[player.UserId] = inFlight
		end
		local now = os.clock()
		local ceiling = self.config.RequestAbandonSeconds or 30
		local active = 0
		for id, startedAt in inFlight do
			if now - startedAt > ceiling then
				inFlight[id] = nil
				self.logger:Warning("Abandoned a stuck request slot", {
					Endpoint = name,
					UserId = player.UserId,
					HeldSeconds = math.floor(now - startedAt),
				})
			else
				active += 1
			end
		end
		if active >= (self.config.MaximumConcurrentRequests or 4) then
			return {
				Success = false,
				Code = "SERVER_BUSY",
				Message = "Please wait before trying again.",
				RequestId = requestId,
			}
		end
		inFlight[requestId] = now
		local ok, result = pcall(handler, player, payload, requestId)
		inFlight[requestId] = nil
		if not ok then
			self.logger:Error("Remote handler failed", {
				Endpoint = name,
				RequestId = requestId,
				Error = tostring(result),
			})
			return {
				Success = false,
				Code = "SERVER_ERROR",
				Message = "The request could not be completed.",
				RequestId = requestId,
			}
		end
		if type(result) ~= "table" then
			self.logger:Error(
				"Remote handler returned an invalid response",
				{ Endpoint = name, RequestId = requestId }
			)
			return {
				Success = false,
				Code = "SERVER_ERROR",
				Message = "The request could not be completed.",
				RequestId = requestId,
			}
		end
		result.RequestId = requestId
		return result
	end
end

-- Published once every endpoint is registered so clients can distinguish "the
-- server is still starting" from "this endpoint genuinely does not exist".
function NetworkServer:MarkReady()
	self.folder:SetAttribute("Ready", true)
end

function NetworkServer:Destroy()
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
	table.clear(self.active)
end

function NetworkServer:RegisterEvent(name: string): RemoteEvent
	assert(self.endpoints[name] == nil, "Duplicate endpoint: " .. name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = self.folder
	self.endpoints[name] = remote
	return remote
end

return NetworkServer
