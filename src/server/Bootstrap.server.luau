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
	"DataService",
	"SettingsService",
	"AuditService",
	"CommunityService",
	"CommunityServerService",
	"GroupService",
	"ExperienceAccessService",
	"AccessService",
	"GamepassService",
	"CharacterService",
	"EconomyService",
	"ProgressionService",
	"ApplicationService",
	"EmploymentService",
	"JobService",
	"ShiftService",
	"QualificationService",
	"VehicleOwnershipService",
	"VehicleService",
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
	"TeamService",
	"RoleService",
	"StationService",
	"UniformService",
	"LoadoutService",
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
	"EmergencyTriggerService",
	"PhoneService",
	"NeedsService",
	"StartMenuService",
	"NetworkService",
}

for _, name in serviceOrder do
	registry:Register(name, require(script.Parent.Services[name]))
end

local ok, problem = pcall(function()
	registry:Initialise(context)
	registry:Start(context)
end)
if not ok then
	logger:Error("RoleplayOS startup failed", { Error = tostring(problem) })
	error(problem, 0)
end

game:BindToClose(function()
	registry:Destroy(context)
	context.Network:Destroy()
end)
logger:Info("RoleplayOS started", {
	ServiceCount = #serviceOrder,
	SchemaVersion = Config.Framework.SchemaVersion,
})
