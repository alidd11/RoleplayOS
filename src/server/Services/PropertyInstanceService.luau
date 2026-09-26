--!strict
local ServerStorage = game:GetService("ServerStorage")

local PropertyInstanceService = {
	instances = {},
	occupants = {},
	unloadVersions = {},
	running = false,
}

function PropertyInstanceService:Init(context: any)
	self.context = context
end

function PropertyInstanceService:Start()
	self.running = true
end

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
	self.unloadVersions[propertyId] = (self.unloadVersions[propertyId] or 0) + 1
	return instance, nil
end

function PropertyInstanceService:SetOccupied(propertyId: string, delta: number)
	local occupants = math.max(0, (self.occupants[propertyId] or 0) + delta)
	self.occupants[propertyId] = occupants

	-- Every occupancy transition invalidates an older zero-occupant timer. Without
	-- this, leave -> re-enter -> leave could let the first timer unload an interior
	-- only seconds after the later departure instead of granting a fresh grace period.
	local version = (self.unloadVersions[propertyId] or 0) + 1
	self.unloadVersions[propertyId] = version
	if occupants ~= 0 then
		return
	end

	local instance = self.instances[propertyId]
	if not instance then
		self.occupants[propertyId] = nil
		self.unloadVersions[propertyId] = nil
		return
	end

	task.delay(30, function()
		if
			not self.running
			or self.unloadVersions[propertyId] ~= version
			or self.occupants[propertyId] ~= 0
			or self.instances[propertyId] ~= instance
		then
			return
		end
		instance:Destroy()
		self.instances[propertyId] = nil
		self.occupants[propertyId] = nil
		self.unloadVersions[propertyId] = nil
	end)
end

function PropertyInstanceService:Destroy()
	self.running = false
	for _, instance in self.instances do
		instance:Destroy()
	end
	table.clear(self.instances)
	table.clear(self.occupants)
	table.clear(self.unloadVersions)
end

return PropertyInstanceService
