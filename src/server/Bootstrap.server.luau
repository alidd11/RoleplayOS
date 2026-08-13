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

-- Config is the immutable source definition. Imported content discovery needs
-- to register runtime vehicles and tools, so give services a narrow mutable
-- catalogue rather than allowing a validator to edit the required module.
local function runtimeConfiguration(source: any): any
	local result = table.clone(source)
	result.Vehicles = table.clone(source.Vehicles or {})
	for id, definition in result.Vehicles do
		local copy = table.clone(definition)
		if type(definition.AssetPath) == "table" then
			copy.AssetPath = table.clone(definition.AssetPath)
		end
		if type(definition.Colours) == "table" then
			copy.Colours = table.clone(definition.Colours)
		end
		if type(definition.RoleIds) == "table" then
			copy.RoleIds = table.clone(definition.RoleIds)
		end
		result.Vehicles[id] = copy
	end
	result.Tools = table.clone(source.Tools or {})
	for id, definition in result.Tools do
		local copy = table.clone(definition)
		if type(definition.AssetPath) == "table" then
			copy.AssetPath = table.clone(definition.AssetPath)
		end
		result.Tools[id] = copy
	end
	result.Dealerships = table.clone(source.Dealerships or {})
	for id, dealership in result.Dealerships do
		local copy = table.clone(dealership)
		copy.VehicleIds = table.clone(dealership.VehicleIds or {})
		result.Dealerships[id] = copy
	end
	result.Loadouts = table.clone(source.Loadouts or {})
	for id, loadout in result.Loadouts do
		local copy = table.clone(loadout)
		copy.ToolIds = table.clone(loadout.ToolIds or {})
		result.Loadouts[id] = copy
	end
	return result
end

local logger = Logger.new("Bootstrap")
local registry = ServiceRegistry.new()
local context = {
	Logger = logger,
	Configuration = runtimeConfiguration(Config),
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
	"MeleeWeaponService",
	"DealerRotationService",
	"VendorService",
	"SpawnService",
	"DutyService",
	"RadioService",
	"PAVAService",
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
	"TaxiService",
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
