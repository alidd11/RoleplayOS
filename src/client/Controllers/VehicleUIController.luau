--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

local VehicleUIController =
	{ connections = {}, vehicleMode = false, state = "OnFoot", suppressed = {} }

function VehicleUIController:Init(context: any)
	self.context = context
	self.settings = Config.Chassis
end

-- The chassis clones its own gauges into PlayerGui when a player takes a seat.
-- Matching them by name is unreliable: forks rename them freely, and a name
-- list is only ever as current as the last fork someone checked. Identify them
-- by behaviour instead. Anything that appears while seated, and is not ours, is
-- the chassis interface, whatever it happens to be called.
--
-- They are disabled rather than destroyed, since the chassis may still be
-- driving them, and re-enabled on leaving the seat so nothing is left broken
-- for a system that expects to own them. The configured names remain as an
-- immediate match for interfaces already present before sitting down.
function VehicleUIController:_suppress(instance: Instance, seated: boolean)
	if not instance:IsA("ScreenGui") or instance:GetAttribute("RoleplayOSManagedUI") then
		return
	end
	local named = table.find(self.settings.SuppressGuiNames, instance.Name) ~= nil
	if not named and not seated then
		return
	end
	if not instance.Enabled then
		return
	end
	instance.Enabled = false
	self.suppressed[instance] = true
end

function VehicleUIController:_restoreSuppressed()
	for instance in self.suppressed do
		if instance.Parent then
			instance.Enabled = true
		end
	end
	table.clear(self.suppressed)
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
	if not enabled then
		self:_restoreSuppressed()
	else
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		for _, child in if playerGui then playerGui:GetChildren() else {} do
			self:_suppress(child, true)
		end
	end
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
		self:_suppress(child, false)
	end
	table.insert(
		self.connections,
		playerGui.ChildAdded:Connect(function(child)
			-- Deferred: the chassis parents its interface and then enables it, so
			-- reading Enabled in the same frame can see the wrong value.
			task.defer(function()
				self:_suppress(child, self.vehicleMode)
			end)
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
