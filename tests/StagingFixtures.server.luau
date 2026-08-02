--!strict
-- Acceptance-place only. Production maps must tag authored instances directly.

local CollectionService = game:GetService("CollectionService")

local fixtures = workspace:WaitForChild("RoleplayOS_STAGING_FIXTURES", 10)
if not fixtures then
	warn("RoleplayOS staging fixtures are unavailable")
	return
end

local tagsByName = {
	CellSpawn = "RoleplayOSCustodyCellSpawn",
	CustodyBookingDesk = "RoleplayOSCustodyDesk",
	CustodyVehicleSeat = "RoleplayOSCustodySeat",
	DealershipNPCDesk = "RoleplayOSVehicleTerminal",
	DealershipVehicleSpawn = "RoleplayOSVehicleSpawn",
	PoliceVehicleTerminal = "RoleplayOSVehicleTerminal",
	PoliceVehicleSpawn = "RoleplayOSVehicleSpawn",
}

for name, tag in tagsByName do
	local instance = fixtures:FindFirstChild(name, true)
	if instance then
		CollectionService:AddTag(instance, tag)
	else
		warn(string.format("RoleplayOS fixture %s is missing", name))
	end
end
