--!strict
-- Read-only runtime wiring checks for the dedicated staging/test place.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

type Result = {
	Level: "PASS" | "WARN" | "FAIL",
	Name: string,
	Detail: string,
}

local results: { Result } = {}

local function record(level: "PASS" | "WARN" | "FAIL", name: string, detail: string)
	table.insert(results, { Level = level, Name = name, Detail = detail })
	local line = string.format("[RoleplayOS Acceptance] %s | %s | %s", level, name, detail)
	if level == "FAIL" then
		warn(line)
	else
		print(line)
	end
end

local function check(condition: boolean, name: string, detail: string)
	record(if condition then "PASS" else "FAIL", name, detail)
end

local roleplayOS = ReplicatedStorage:WaitForChild("RoleplayOS", 20)
check(roleplayOS ~= nil, "bootstrap.replication", "ReplicatedStorage.RoleplayOS is present")
if not roleplayOS then
	error("RoleplayOS did not replicate within 20 seconds", 0)
end

local network = roleplayOS:WaitForChild("Network", 10)
local remotes = if network then network:WaitForChild("Remotes", 20) else nil
check(remotes ~= nil, "bootstrap.network", "Network remotes were created")

local expectedFunctions = {
	"GetFrameworkStatus",
	"GetStartMenu",
	"CreateCharacter",
	"SelectCharacter",
	"GetMDTAccess",
	"GetDispatchSnapshot",
	"DispatchCreateCall",
	"DispatchAssignUnit",
	"GetVehicleSpawnMenu",
	"SpawnOwnedVehicle",
	"SpawnServiceVehicle",
	"PurchaseVehicle",
	"CuffPlayer",
	"BookCustody",
	"GetPresentedId",
	"GetPhone",
	"PhoneEmergency",
	"SetSprintState",
	"PurchaseFood",
}

if remotes then
	for _, name in expectedFunctions do
		local remote = remotes:FindFirstChild(name)
		check(
			remote ~= nil and remote:IsA("RemoteFunction"),
			"network." .. name,
			"authoritative RemoteFunction exists"
		)
	end
	for _, name in { "DispatchChanged", "ANPRAlert", "NeedsChanged", "PhoneChanged" } do
		local remote = remotes:FindFirstChild(name)
		check(
			remote ~= nil and remote:IsA("RemoteEvent"),
			"network." .. name,
			"server-to-client RemoteEvent exists"
		)
	end
end

local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
check(assets ~= nil, "content.root", "ServerStorage.RoleplayOSAssets exists")
for _, path in
	{
		{ "Vehicles", "Civilian", "Starter" },
		{ "Vehicles", "Services", "Police", "Frontline" },
		{ "Vehicles", "Services", "Police", "ArmedResponse" },
		{ "Vehicles", "Services", "Police", "RoadsPolicing" },
		{ "Tools", "Civilian" },
		{ "Tools", "Services", "Police", "Shared" },
	}
do
	local current: Instance? = assets
	for _, segment in path do
		current = if current then current:FindFirstChild(segment) else nil
	end
	check(current ~= nil, "content." .. table.concat(path, "."), "authoring folder exists")
end

if assets then
	local unsafe = {}
	for _, descendant in assets:GetDescendants() do
		if
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("RemoteEvent")
			or descendant:IsA("RemoteFunction")
			or descendant:IsA("BindableEvent")
			or descendant:IsA("BindableFunction")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
		then
			table.insert(unsafe, descendant:GetFullName())
		end
	end
	check(
		#unsafe == 0,
		"content.no-executables",
		if #unsafe == 0
			then "assets contain geometry/configuration only"
			else table.concat(unsafe, ", ")
	)
end

local config = require(roleplayOS.Config.Config)
local dispatchSeats = CollectionService:GetTagged(config.Dispatch.SeatTag)
record(
	if #dispatchSeats > 0 then "PASS" else "WARN",
	"world.dispatch-seats",
	string.format("%d tagged dispatch seat(s)", #dispatchSeats)
)
local anprSensors = CollectionService:GetTagged(config.ANPR.SensorTag)
record(
	if #anprSensors > 0 then "PASS" else "WARN",
	"world.anpr-sensors",
	string.format("%d tagged ANPR sensor(s)", #anprSensors)
)

local failures = 0
local warnings = 0
for _, result in results do
	if result.Level == "FAIL" then
		failures += 1
	elseif result.Level == "WARN" then
		warnings += 1
	end
end

local status = Instance.new("Folder")
status.Name = "AcceptanceStatus"
status:SetAttribute("Completed", true)
status:SetAttribute("Failures", failures)
status:SetAttribute("Warnings", warnings)
status:SetAttribute("Checks", #results)
status:SetAttribute("ServerJobId", game.JobId)
status.Parent = roleplayOS

print(
	string.format(
		"[RoleplayOS Acceptance] COMPLETE | %d checks | %d failure(s) | %d warning(s) | JobId=%s",
		#results,
		failures,
		warnings,
		game.JobId
	)
)

if failures > 0 then
	error(string.format("RoleplayOS runtime acceptance failed with %d failure(s)", failures), 0)
end
