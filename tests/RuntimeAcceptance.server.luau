--!strict
-- Read-only runtime wiring checks for the dedicated staging/test place.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")

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
	"MDTCreateWarrant",
	"MDTRevokeWarrant",
	"MDTGetIncidents",
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
	"PhoneSendText",
	"PhonePlaceCall",
	"PhoneAnswerCall",
	"PhoneEndCall",
	"PhoneEmergency",
	"PhoneToggleFlashlight",
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

local phoneVoice = SoundService:WaitForChild("RoleplayOSPhoneVoice", 10)
check(
	phoneVoice ~= nil and phoneVoice:IsA("Folder"),
	"phone.voice-router",
	"optional Audio API call router initialised"
)

if RunService:IsStudio() then
	local services = ServerScriptService:WaitForChild("RoleplayOS", 10)
		and ServerScriptService.RoleplayOS:WaitForChild("Services", 10)
	if services then
		local dataService = require(services.DataService)
		local recordIndex = require(services.RecordIndexService)
		local characterId = "STUDIO_ACCEPTANCE_OFFLINE_RECORD"
		local personKey = "Person:" .. characterId
		dataService:UpdateMdtRecord(personKey, function(_existing)
			return {
				RecordType = "Person",
				CharacterId = characterId,
				FullName = "Zzacceptance Offline",
				DateOfBirth = "2000-01-01",
				Licences = {},
				DrivingRecord = { Points = 0, Fines = {} },
				CustodyRecord = { Bookings = {} },
				CriminalRecord = {},
				Warrants = {},
				UpdatedAt = os.time(),
			}
		end)
		dataService:UpdateMdtIndex("Person:zz", function(_existing)
			return {
				Entries = {
					[characterId] = {
						CharacterId = characterId,
						FullName = "Zzacceptance Offline",
						SearchText = "zzacceptance offline|offline zzacceptance",
						UpdatedAt = os.time(),
					},
				},
			}
		end)
		local search = select(1, recordIndex:SearchPeople("zzacceptance", 1))
		check(
			search ~= nil and search.Total == 1 and search.Items[1].CharacterId == characterId,
			"mdt.offline-index",
			"durable record search does not depend on a live Player"
		)
		dataService:UpdateMdtRecord(personKey, function(_existing)
			return nil
		end)
		dataService:UpdateMdtIndex("Person:zz", function(_existing)
			return nil
		end)
	else
		check(false, "mdt.offline-index", "server service folder unavailable")
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
