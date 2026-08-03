--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

local VehicleUIController = { connections = {}, vehicleMode = false, state = "OnFoot" }

function VehicleUIController:Init(context: any)
	self.context = context
	self.settings = Config.Chassis
end

-- The chassis clones its own gauges into PlayerGui when a player takes a seat.
-- RoleplayOS presents the readouts itself, so the chassis interface is disabled
-- on sight rather than left to sit alongside a second set of gauges. It is
-- disabled rather than destroyed: the chassis may still be driving it, and
-- removing something another system owns invites errors that are hard to trace
-- back here.
function VehicleUIController:_suppress(instance: Instance)
	if not instance:IsA("ScreenGui") then
		return
	end
	if instance:GetAttribute("RoleplayOSManagedUI") then
		return
	end
	if table.find(self.settings.SuppressGuiNames, instance.Name) then
		instance.Enabled = false
	end
end

function VehicleUIController:_broadcast()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute("RoleplayOSVehicleMode", self.vehicleMode)
	end
	self.context.Events.VehicleModeChanged:Fire(self.vehicleMode)
	self.context.Events.UIStateChanged:Fire(self.state)
end

function VehicleUIController:_setSeat(seatPart: BasePart?)
	local state = "OnFoot"
	if seatPart and CollectionService:HasTag(seatPart, "RoleplayOSDispatchSeat") then
		state = "DispatchSeat"
	elseif seatPart and seatPart:IsA("VehicleSeat") then
		state = if seatPart.Occupant then "Driver" else "Passenger"
	elseif seatPart then
		state = "Passenger"
	end
	local enabled = state == "Driver" or state == "Passenger"
	if self.vehicleMode == enabled and self.state == state then
		return
	end
	self.vehicleMode = enabled
	self.state = state
	self:_broadcast()
end

function VehicleUIController:_watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	table.insert(
		self.connections,
		humanoid.Seated:Connect(function(active, seatPart)
			self:_setSeat(if active then seatPart else nil)
		end)
	)
	table.insert(
		self.connections,
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			local seatPart = humanoid.SeatPart
			self:_setSeat(seatPart)
		end)
	)
	self:_setSeat(humanoid.SeatPart)
end

function VehicleUIController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, child in playerGui:GetChildren() do
		self:_suppress(child)
	end
	table.insert(
		self.connections,
		playerGui.ChildAdded:Connect(function(child)
			self:_suppress(child)
		end)
	)
	local player = Players.LocalPlayer
	self:_broadcast()
	if player.Character then
		self:_watchCharacter(player.Character)
	end
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			self:_setSeat(nil)
			self:_watchCharacter(character)
		end)
	)
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(
			self.connections,
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self:_broadcast()
			end)
		)
	end
end

function VehicleUIController:IsActive(): boolean
	return self.vehicleMode
end

function VehicleUIController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return VehicleUIController
