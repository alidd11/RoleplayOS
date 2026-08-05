--!strict
local FeatureController = require(script.Controllers.FeatureController)
local events = {
	StartMenuChanged = Instance.new("BindableEvent"),
	DispatchChanged = Instance.new("BindableEvent"),
	SettingsChanged = Instance.new("BindableEvent"),
	CharacterChanged = Instance.new("BindableEvent"),
	DutyChanged = Instance.new("BindableEvent"),
	VehicleModeChanged = Instance.new("BindableEvent"),
	UIStateChanged = Instance.new("BindableEvent"),
}
for name, event in events do
	event.Name = name
	event.Parent = script
end
local controllers = {
	UIOrchestrator = require(script.Controllers.UIOrchestrator),
	ControlsController = require(script.Controllers.ControlsController),
	NetworkController = require(script.Controllers.NetworkController),
	NotificationController = require(script.Controllers.NotificationController),
	SettingsController = require(script.Controllers.SettingsController),
	CharacterController = require(script.Controllers.CharacterController),
	ProgressionController = require(script.Controllers.ProgressionController),
	MinimapController = require(script.Controllers.MinimapController),
	LocationController = require(script.Controllers.LocationController),
	PhoneController = require(script.Controllers.PhoneController),
	GamepassController = require(script.Controllers.GamepassController),
	VendorController = require(script.Controllers.VendorController),
	ApplicationController = require(script.Controllers.ApplicationController),
	MDTController = require(script.Controllers.MDTController),
	DispatchController = require(script.Controllers.DispatchController),
	EmergencyAlertController = require(script.Controllers.EmergencyAlertController),
	CCTVController = require(script.Controllers.CCTVController),
	ANPRAlertController = require(script.Controllers.ANPRAlertController),
	NeedsController = require(script.Controllers.NeedsController),
	VehicleUIController = require(script.Controllers.VehicleUIController),
	DrivingControlsController = require(script.Controllers.DrivingControlsController),
	EmergencyLightsController = require(script.Controllers.EmergencyLightsController),
	DealershipController = require(script.Controllers.DealershipController),
	SpeedometerController = require(script.Controllers.SpeedometerController),
	PublicSafetyController = require(script.Controllers.PublicSafetyController),
	CustodyController = require(script.Controllers.CustodyController),
	CommunityController = require(script.Controllers.CommunityController),
	DutyController = require(script.Controllers.DutyController),
	StartMenuController = require(script.Controllers.StartMenuController),
}
for _, name in
	{ "AccessPrompts", "Jobs", "Vehicles", "Properties", "Furniture", "EmergencyServices" }
do
	controllers[name .. "Controller"] = FeatureController.new(name)
end
local context = { Controllers = controllers, Events = events }

-- One ordered list drives both lifecycle phases. Keeping two copies in sync by
-- hand risks a controller being initialised but never started, or vice versa.
local ORDER = {
	"UIOrchestrator",
	"ControlsController",
	"NetworkController",
	"NotificationController",
	"SettingsController",
	"CharacterController",
	"ProgressionController",
	"MinimapController",
	"LocationController",
	"PhoneController",
	"GamepassController",
	"VendorController",
	"ApplicationController",
	"MDTController",
	"DispatchController",
	"EmergencyAlertController",
	"CCTVController",
	"ANPRAlertController",
	"NeedsController",
	"VehicleUIController",
	"DrivingControlsController",
	"EmergencyLightsController",
	"DealershipController",
	"SpeedometerController",
	"PublicSafetyController",
	"CustodyController",
	"CommunityController",
	"DutyController",
	"AccessPromptsController",
	"JobsController",
	"VehiclesController",
	"PropertiesController",
	"FurnitureController",
	"EmergencyServicesController",
	"StartMenuController",
}

-- Init must stay serial and in order: controllers read each other's stored
-- dependencies. It does no networking, so it cannot yield indefinitely.
for _, name in ORDER do
	-- Serial and in order, because controllers read each other's stored
	-- dependencies, but isolated: one that throws here used to kill the script
	-- before the start menu was mounted, so a single bad controller produced a
	-- blank screen rather than a menu missing one feature.
	local ok, problem = pcall(function()
		controllers[name]:Init(context)
	end)
	if not ok then
		warn(
			string.format(
				"RoleplayOS controller %s failed to initialise: %s",
				name,
				tostring(problem)
			)
		)
	end
end

-- Start connects events and issues first requests, so it can yield on remotes
-- the server has not registered yet. Each one is isolated: a controller that
-- hangs or errors must not prevent the rest of the interface from starting.
for _, name in ORDER do
	task.spawn(function()
		local ok, problem = pcall(function()
			controllers[name]:Start()
		end)
		if not ok then
			warn(
				string.format(
					"RoleplayOS controller %s failed to start: %s",
					name,
					tostring(problem)
				)
			)
		end
	end)
end

-- Mounted inside a pcall of its own. It is the last thing to run and the one
-- the player actually looks at, so a failure here is the difference between a
-- menu and an empty screen, and it should say so rather than vanish.
local mounted, mountProblem = pcall(function()
	require(script.UI.DeveloperDashboard).mount(context)
end)
if not mounted then
	warn("RoleplayOS start menu failed to mount: " .. tostring(mountProblem))
end
