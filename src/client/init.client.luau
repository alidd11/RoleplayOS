--!strict
local FeatureController = require(script.Controllers.FeatureController)
local events = {
	StartMenuChanged = Instance.new("BindableEvent"),
	DispatchChanged = Instance.new("BindableEvent"),
}
local controllers = {
	NetworkController = require(script.Controllers.NetworkController),
	NotificationController = require(script.Controllers.NotificationController),
	CharacterController = require(script.Controllers.CharacterController),
	GamepassController = require(script.Controllers.GamepassController),
	ApplicationController = require(script.Controllers.ApplicationController),
	MDTController = require(script.Controllers.MDTController),
	DispatchController = require(script.Controllers.DispatchController),
	CommunityController = require(script.Controllers.CommunityController),
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
		"CharacterController",
		"GamepassController",
		"ApplicationController",
		"MDTController",
		"DispatchController",
		"CommunityController",
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
		"CharacterController",
		"GamepassController",
		"ApplicationController",
		"MDTController",
		"DispatchController",
		"CommunityController",
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
