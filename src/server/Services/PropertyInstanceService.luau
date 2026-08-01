--!strict
local ServerStorage = game:GetService("ServerStorage")
local PropertyInstanceService = { instances = {}, occupants = {} }
function PropertyInstanceService:Init(context: any)
	self.context = context
end
function PropertyInstanceService:Start() end
function PropertyInstanceService:Load(propertyId: string): (Model?, string?)
	if self.instances[propertyId] then
		return self.instances[propertyId], nil
	end
	local definition = self.context.Configuration.Properties[propertyId]
	local templates = ServerStorage.RoleplayOSAssets.PropertyInteriors
	local template = definition and templates:FindFirstChild(definition.InteriorTemplate)
	if not template or not template:IsA("Model") then
		return nil, "INTERIOR_TEMPLATE_UNAVAILABLE"
	end
	local instance = template:Clone()
	instance.Name = "Property_" .. propertyId
	instance.Parent = workspace
	self.instances[propertyId] = instance
	self.occupants[propertyId] = 0
	return instance, nil
end
function PropertyInstanceService:SetOccupied(propertyId: string, delta: number)
	self.occupants[propertyId] = math.max(0, (self.occupants[propertyId] or 0) + delta)
	if self.occupants[propertyId] == 0 then
		task.delay(30, function()
			if self.occupants[propertyId] == 0 and self.instances[propertyId] then
				self.instances[propertyId]:Destroy()
				self.instances[propertyId] = nil
			end
		end)
	end
end
function PropertyInstanceService:Destroy()
	for _, instance in self.instances do
		instance:Destroy()
	end
	table.clear(self.instances)
end
return PropertyInstanceService
