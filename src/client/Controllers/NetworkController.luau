--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkController = {}
-- Endpoints are registered by NetworkService, which starts after every other
-- server service. A client request issued during that window must wait for the
-- endpoint rather than reporting the feature as missing.
local ENDPOINT_TIMEOUT_SECONDS = 15
-- Longer than the server's own abandon ceiling, so a request the server has
-- already given up on is reported here rather than appearing to still be
-- running.
local REQUEST_TIMEOUT_SECONDS = 35

function NetworkController:Init(_context: any)
	self.remotes =
		ReplicatedStorage:WaitForChild("RoleplayOS"):WaitForChild("Network"):WaitForChild("Remotes")
	self.resolved = {}
end
function NetworkController:Start() end
function NetworkController:_awaitReady()
	if self.ready or self.remotes:GetAttribute("Ready") then
		self.ready = true
		return
	end
	local deadline = os.clock() + ENDPOINT_TIMEOUT_SECONDS
	while os.clock() < deadline do
		task.wait(0.1)
		if self.remotes:GetAttribute("Ready") then
			self.ready = true
			return
		end
	end
end
function NetworkController:Resolve(endpoint: string): RemoteFunction?
	local cached = self.resolved[endpoint]
	if cached and cached.Parent then
		return cached
	end
	local remote = self.remotes:FindFirstChild(endpoint)
	if not remote then
		-- Wait once for the whole endpoint set rather than per endpoint, so a
		-- genuinely missing name still fails fast after the server is ready.
		self:_awaitReady()
		remote = self.remotes:FindFirstChild(endpoint)
	end
	if not remote or not remote:IsA("RemoteFunction") then
		return nil
	end
	self.resolved[endpoint] = remote
	return remote
end
-- Bounded lookup for RemoteEvents. An untimed WaitForChild here yields forever
-- when the server never reaches that registration, silently wedging the caller.
function NetworkController:ResolveEvent(name: string): RemoteEvent?
	local remote = self.remotes:FindFirstChild(name)
	if not remote then
		self:_awaitReady()
		remote = self.remotes:FindFirstChild(name)
	end
	if not remote or not remote:IsA("RemoteEvent") then
		warn("RoleplayOS remote event unavailable: " .. name)
		return nil
	end
	return remote
end
function NetworkController:Request(endpoint: string, payload: any): any
	local remote = self:Resolve(endpoint)
	if not remote then
		return {
			Success = false,
			Code = "ENDPOINT_UNAVAILABLE",
			Message = "The server is still starting. Try again in a moment.",
			RequestId = "",
		}
	end
	-- InvokeServer cannot be cancelled and never times out on its own, so a
	-- handler that stalls leaves the caller waiting forever with no error. The
	-- interface then shows a button stuck mid-action and the player has no way
	-- to recover. Run the call alongside a deadline and give up waiting on it:
	-- the reply is abandoned rather than cancelled, which is why a late response
	-- must be discarded instead of returned to a caller that moved on.
	local finished = false
	local abandoned = false
	local ok, response = nil, nil
	task.spawn(function()
		local callOk, callResponse = pcall(remote.InvokeServer, remote, payload)
		if abandoned then
			return
		end
		ok, response = callOk, callResponse
		finished = true
	end)
	local deadline = os.clock() + REQUEST_TIMEOUT_SECONDS
	while not finished and os.clock() < deadline do
		task.wait(0.05)
	end
	if not finished then
		abandoned = true
		warn(string.format("RoleplayOS request timed out: %s", endpoint))
		return {
			Success = false,
			Code = "REQUEST_TIMEOUT",
			Message = "The server did not respond. Try again.",
			RequestId = "",
		}
	end
	if not ok or type(response) ~= "table" then
		return {
			Success = false,
			Code = "NETWORK_ERROR",
			Message = "The request could not be sent.",
			RequestId = "",
		}
	end
	return response
end
function NetworkController:Destroy() end
return NetworkController
