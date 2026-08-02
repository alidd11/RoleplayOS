--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RateLimiter = require(ReplicatedStorage.RoleplayOS.Shared.RateLimiter)

local NetworkServer = {}
NetworkServer.__index = NetworkServer

function NetworkServer.new(config: any, logger: any)
	local folder = ReplicatedStorage.RoleplayOS.Network:FindFirstChild("Remotes")
		or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage.RoleplayOS.Network
	return setmetatable(
		{ folder = folder, config = config, logger = logger, endpoints = {}, limiters = {} },
		NetworkServer
	)
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
	local limits = self.config.Endpoints[name] or { Capacity = 2, RefillPerSecond = 0.5 }
	local limiter = RateLimiter.new(limits.Capacity, limits.RefillPerSecond)
	self.limiters[name] = limiter
	self.endpoints[name] = remote
	remote.OnServerInvoke = function(player: Player, payload: any)
		local requestId = HttpService:GenerateGUID(false)
		if not limiter:Allow(tostring(player.UserId)) then
			return {
				Success = false,
				Code = "RATE_LIMITED",
				Message = "Please wait before trying again.",
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
		local valid, reason = schema(payload)
		if not valid then
			self.logger:Security(
				"Rejected remote payload",
				{ Endpoint = name, UserId = player.UserId, Reason = reason }
			)
			return {
				Success = false,
				Code = "INVALID_REQUEST",
				Message = "The request was invalid.",
				RequestId = requestId,
			}
		end
		local ok, result = pcall(handler, player, payload, requestId)
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
		result.RequestId = requestId
		return result
	end
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
