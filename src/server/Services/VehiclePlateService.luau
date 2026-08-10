--!strict

-- Keeps imported vehicles' own plate geometry and artwork. RoleplayOS only
-- supplies the server-authored registration text used by persistence and ANPR.
local Workspace = game:GetService("Workspace")
local VehiclePlateService = {}

local function compact(value: string): string
	return string.lower(value):gsub("[^%w]", "")
end

function VehiclePlateService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.VehicleIdentity
	self.plateNames = {}
	for _, name in self.settings.PlatePartNames or {} do
		self.plateNames[compact(name)] = true
	end
	self.textNames = {}
	for _, name in self.settings.PlateTextNames or {} do
		self.textNames[compact(name)] = true
	end
end

function VehiclePlateService:Start() end

-- ServiceRegistry calls Destroy on every successfully started service during
-- shutdown. This service owns no connections or transient instances, but it
-- still implements the lifecycle contract so stopping a Studio session does
-- not raise an error.
function VehiclePlateService:Destroy() end

function VehiclePlateService:_isPlateRoot(instance: Instance): boolean
	if instance:GetAttribute("RoleplayOSPlate") == true then
		return true
	end
	return self.plateNames[compact(instance.Name)] == true
end

function VehiclePlateService:_isPlateText(instance: Instance): boolean
	if instance:GetAttribute("RoleplayOSPlateText") == true then
		return true
	end
	if self.textNames[compact(instance.Name)] then
		return true
	end
	local current = instance.Parent
	while current do
		if self:_isPlateRoot(current) then
			local textCount = 0
			for _, descendant in current:GetDescendants() do
				if
					descendant:IsA("TextLabel")
					or descendant:IsA("TextButton")
					or descendant:IsA("TextBox")
				then
					textCount += 1
				end
			end
			-- A single label is unambiguously the registration. More elaborate
			-- designs may also contain a country mark or maker text, so those must
			-- name/attribute the registration label explicitly.
			return textCount == 1
		end
		current = current.Parent
	end
	return false
end

function VehiclePlateService:Apply(vehicle: Model, registration: string): number
	vehicle:SetAttribute("RoleplayOSRegistration", registration)
	local changed = 0
	for _, instance in vehicle:GetDescendants() do
		if
			(instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
			and self:_isPlateText(instance)
		then
			instance.Text = registration
			changed += 1
		elseif instance:IsA("StringValue") and self:_isPlateText(instance) then
			instance.Value = registration
			changed += 1
		end
	end
	return changed
end

function VehiclePlateService:RefreshOwned(
	ownerUserId: number,
	vehicleId: string,
	registration: string
): boolean
	for _, instance in Workspace:GetDescendants() do
		if
			instance:IsA("Model")
			and instance:GetAttribute("RoleplayOSOwnerUserId") == ownerUserId
			and instance:GetAttribute("RoleplayOSVehicleId") == vehicleId
		then
			self:Apply(instance, registration)
			return true
		end
	end
	return false
end

return VehiclePlateService
