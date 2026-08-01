--!strict
local ServerStorage = game:GetService("ServerStorage")
local LoadoutService = {}
function LoadoutService:Init(context: any)
	self.context = context
end
function LoadoutService:Start() end
function LoadoutService:Apply(player: Player, loadoutId: string): (boolean, string?)
	local definition = self.context.Configuration.Loadouts[loadoutId]
	if not definition then
		return false, "LOADOUT_NOT_FOUND"
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, "BACKPACK_UNAVAILABLE"
	end
	local tools = ServerStorage.RoleplayOSAssets.Tools
	for _, toolName in definition.ToolNames do
		local template = tools:FindFirstChild(toolName)
		if template and template:IsA("Tool") then
			template:Clone().Parent = backpack
		else
			self.context.Logger:Warning(
				"Loadout tool is unavailable",
				{ LoadoutId = loadoutId, Tool = toolName }
			)
		end
	end
	return true, nil
end
function LoadoutService:Destroy() end
return LoadoutService
