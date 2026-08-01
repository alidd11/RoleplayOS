--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkController = {}
function NetworkController:Init(_context: any)
	self.remotes =
		ReplicatedStorage:WaitForChild("RoleplayOS"):WaitForChild("Network"):WaitForChild("Remotes")
end
function NetworkController:Start() end
function NetworkController:Request(endpoint: string, payload: any): any
	local remote = self.remotes:FindFirstChild(endpoint)
	if not remote or not remote:IsA("RemoteFunction") then
		return {
			Success = false,
			Code = "ENDPOINT_UNAVAILABLE",
			Message = "This feature is not available.",
			RequestId = "",
		}
	end
	local ok, response = pcall(remote.InvokeServer, remote, payload)
	if not ok then
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
