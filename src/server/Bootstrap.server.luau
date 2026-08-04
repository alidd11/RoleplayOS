--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	-- Fills the vehicle catalogue from the asset folders, so it must run before
	-- anything reads or validates that list.
	"VehicleCatalogueService",
	"DataService",
	"RecordIndexService",
	"SettingsService",
	"AuditService",
	"CommunityService",
	"CommunityServerService",
	"OfficialServerService",
	"GroupService",
	"ExperienceAccessService",
	"AccessService",
	"GamepassService",
	"CharacterService",
	"EconomyService",
	"ProgressionService",
	"ApplicationService",
	"EmploymentService",
	"PayrollService",
	"JobService",
	"ShiftService",
	"QualificationService",
	"ContentValidationService",
	"VehicleOwnershipService",
	"VehiclePreviewService",
	"VehicleService",
	"RoadSafetyService",
	"CustodyService",
	"IdentificationService",
	"UKTimeService",
	"CCTVService",
	"DealershipService",
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
	"UniformService",
	"LoadoutService",
	"VendorService",
	"SpawnService",
	"DutyService",
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
	"PhoneVoiceService",
	"PhoneService",
	"NeedsService",
	"StartMenuService",
	"NetworkService",
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
game:BindToClose(function()
	registry:Destroy(context)
	context.Network:Destroy()
end)

local ok, problem = pcall(function()
	registry:Initialise(context)
	registry:Start(context)
end)
if not ok then
	-- Reported, not re-raised. A server missing one service is worth far more
	-- than no server at all, and re-raising here only removed the running one.
	logger:Error("RoleplayOS startup failed", { Error = tostring(problem) })
end
logger:Info("RoleplayOS started", {
	ServiceCount = #serviceOrder,
	SchemaVersion = Config.Framework.SchemaVersion,
})
