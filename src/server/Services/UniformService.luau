--!strict
local UniformService = {}
function UniformService:Init(context: any)
	self.context = context
end
function UniformService:Start() end
function UniformService:Apply(player: Player, uniformId: string): (boolean, string?)
	local definition = self.context.Configuration.Uniforms[uniformId]
	local character = player.Character
	if not definition or not character then
		return false, "UNIFORM_UNAVAILABLE"
	end
	for _, className in { "Shirt", "Pants" } do
		local current = character:FindFirstChildOfClass(className)
		if current then
			current:Destroy()
		end
	end
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = definition.ShirtTemplate
	shirt.Parent = character
	local trousers = Instance.new("Pants")
	trousers.PantsTemplate = definition.TrousersTemplate
	trousers.Parent = character
	return true, nil
end
function UniformService:Destroy() end
return UniformService
