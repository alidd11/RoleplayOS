--!strict
local FeatureController = require(script.Controllers.FeatureController)
local events = {
	StartMenuChanged = Instance.new("BindableEvent"),
	DispatchChanged = Instance.new("BindableEvent"),
	SettingsChanged = Instance.new("BindableEvent"),
	CharacterChanged = Instance.new("BindableEvent"),
	DutyChanged = Instance.new("BindableEvent"),
	VehicleModeChanged = Instance.new("BindableEvent"),
}
local controllers = {
	NetworkController = require(script.Controllers.NetworkController),
	NotificationController = require(script.Controllers.NotificationController),
	SettingsController = require(script.Controllers.SettingsController),
	CharacterController = require(script.Controllers.CharacterController),
	ProgressionController = require(script.Controllers.ProgressionController),
	MinimapController = require(script.Controllers.MinimapController),
	PhoneController = require(script.Controllers.PhoneController),
	GamepassController = require(script.Controllers.GamepassController),
	ApplicationController = require(script.Controllers.ApplicationController),
	MDTController = require(script.Controllers.MDTController),
	DispatchController = require(script.Controllers.DispatchController),
	EmergencyAlertController = require(script.Controllers.EmergencyAlertController),
	CCTVController = require(script.Controllers.CCTVController),
	ANPRAlertController = require(script.Controllers.ANPRAlertController),
	CustomRegistrationController = require(script.Controllers.CustomRegistrationController),
	NeedsController = require(script.Controllers.NeedsController),
	VehicleUIController = require(script.Controllers.VehicleUIController),
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
for _, name in
	{
		"NetworkController",
		"NotificationController",
		"SettingsController",
		"CharacterController",
		"ProgressionController",
		"MinimapController",
		"PhoneController",
		"GamepassController",
		"ApplicationController",
		"MDTController",
		"DispatchController",
		"EmergencyAlertController",
		"CCTVController",
		"ANPRAlertController",
		"CustomRegistrationController",
		"NeedsController",
		"VehicleUIController",
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
do
	controllers[name]:Init(context)
end
for _, name in
	{
		"NetworkController",
		"NotificationController",
		"SettingsController",
		"CharacterController",
		"ProgressionController",
		"MinimapController",
		"PhoneController",
		"GamepassController",
		"ApplicationController",
		"MDTController",
		"DispatchController",
		"EmergencyAlertController",
		"CCTVController",
		"ANPRAlertController",
		"CustomRegistrationController",
		"NeedsController",
		"VehicleUIController",
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
do
	controllers[name]:Start()
end

if game:GetService("RunService"):IsStudio() then
	require(script.UI.DeveloperDashboard).mount(context)
end
