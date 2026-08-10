--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)
local ConfigValidator = require(ReplicatedStorage.RoleplayOS.Shared.ConfigValidator)
local Logger = require(ReplicatedStorage.RoleplayOS.Shared.Logger)
local ServiceRegistry = require(script.Parent.Systems.ServiceRegistry)
local NetworkServer = require(script.Parent.Systems.NetworkServer)

local valid, errors = ConfigValidator.validate(Config)
if not valid then
	error("Invalid RoleplayOS configuration:\n" .. table.concat(errors, "\n"), 0)
end

local logger = Logger.new("Bootstrap")
local registry = ServiceRegistry.new()
local context = {
	Logger = logger,
	Configuration = Config,
	Services = registry,
	Sessions = {},
	Network = NetworkServer.new(Config.Network, logger),
}

local serviceOrder = {
	"DataService",
	"RecordIndexService",
	"SettingsService",
	"AuditService",
	"ServerModeService",
	"OfficialServerService",
	"GroupService",
	"ExperienceAccessService",
	"AccessService",
	"GamepassService",
	"DeveloperProductService",
	"CharacterService",
	"EconomyService",
	"MoneyDropService",
	"ProgressionService",
	"ApplicationService",
	"EmploymentService",
	"PayrollService",
	"JobService",
	"ShiftService",
	"QualificationService",
	"ContentValidationService",
	"WorldBudgetService",
	"VehicleOwnershipService",
	"VehiclePlateService",
	"VehicleSpawnerService",
	"DiscordFineService",
	"RoadSafetyService",
	"CustodyService",
	"IdentificationService",
	"UKTimeService",
	"CCTVService",
	"GarageService",
	"PropertyService",
	"PropertyInstanceService",
	"EstateAgentService",
	"FurnitureService",
	"FurniturePlacementService",
	"FurnitureStoreService",
	"InventoryService",
	"BusinessService",
	"DepartmentService",
	"ShoulderNumberService",
	"TeamService",
	"RoleService",
	"StationService",
	"AvatarNormalizationService",
	"UniformService",
	"LoadoutService",
	"VendorService",
	"SpawnService",
	"DutyService",
	"RadioService",
	"EmergencyLightsService",
	"MDTService",
	"PersonRecordService",
	"VehicleRecordService",
	"IncidentService",
	"WarrantService",
	"UnitService",
	"CallService",
	"DispatchService",
	"ANPRService",
	"EmergencyTriggerService",
	"ImportedSystemAdapterService",
	"BankRobberyService",
	"PhoneVoiceService",
	"PhoneService",
	"NeedsService",
	"StartMenuService",
	"NetworkService",
	"HealthService",
}

for _, name in serviceOrder do
	registry:Register(name, require(script.Parent.Services[name]))
end

-- Armed before anything is started.
--
-- Registered after startup, a service that threw took the whole script down
-- before this line ran, so nothing was ever bound: the services that had already
-- started kept running, and when the server eventually closed no Destroy ran at
-- all. Every online player lost the time since their last autosave and left a
-- stamped lease behind that locked them out of every other server.
local tornDown = false
local function tearDown()
	if tornDown then
		return
	end
	tornDown = true
	registry:Destroy(context)
	context.Network:Destroy()
end

game:BindToClose(tearDown)

local ok, problem = pcall(function()
	registry:Initialise(context)
	registry:Start(context)
end)
if not ok then
	local diagnostic = string.gsub(tostring(problem), "[\r\n]+", " ")
	if #diagnostic > 180 then
		diagnostic = string.sub(diagnostic, 1, 180)
	end
	logger:Error("RoleplayOS startup failed", { Error = diagnostic })
	tearDown()
	-- Keep the detailed diagnostic in trusted server logs. Returning internal
	-- service paths and implementation errors in a player-facing kick leaks
	-- architecture and turns a safe startup refusal into a security disclosure.
	local message = "This server could not start safely. Please join another server."
	for _, player in Players:GetPlayers() do
		player:Kick(message)
	end
	Players.PlayerAdded:Connect(function(player)
		player:Kick(message)
	end)
	return
end
logger:Info("RoleplayOS started", {
	ServiceCount = #serviceOrder,
	SchemaVersion = Config.Framework.SchemaVersion,
})
