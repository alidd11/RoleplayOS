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

-- Bounded. The remotes folder is created by the server, so if the server script
-- dies during startup it never appears at all. Waiting for it without a limit
-- blocked the serial Init loop forever, which meant the start menu, which is
-- mounted after that loop, never appeared and nothing said why: a blank screen
-- with no error is the least diagnosable failure this client has.
--
-- Giving up leaves the controller usable and every request reports that the
-- server is unavailable, which is both true and visible.
local REMOTES_TIMEOUT_SECONDS = 20

function NetworkController:Init(_context: any)
	self.resolved = {}
	local root = ReplicatedStorage:WaitForChild("RoleplayOS", REMOTES_TIMEOUT_SECONDS)
	local network = if root then root:WaitForChild("Network", REMOTES_TIMEOUT_SECONDS) else nil
	self.remotes = if network then network:WaitForChild("Remotes", REMOTES_TIMEOUT_SECONDS) else nil
	if not self.remotes then
		warn(
			"RoleplayOS could not find the server's remotes. The server did not finish "
				.. "starting, so nothing that needs it will work. The menu is still usable."
		)
	end
end
function NetworkController:Start() end
function NetworkController:_awaitReady()
	if not self.remotes then
		return
	end
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
	if not self.remotes then
		return nil
	end
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
	if not self.remotes then
		return nil
	end
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
