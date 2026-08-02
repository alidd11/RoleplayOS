--!strict

local Players = game:GetService("Players")

local VehicleUIController = { connections = {}, vehicleMode = false }

function VehicleUIController:Init(context: any)
	self.context = context
end

function VehicleUIController:_broadcast()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute("RoleplayOSVehicleMode", self.vehicleMode)
		playerGui:SetAttribute("RoleplayOSReservedRightPixels", if self.vehicleMode then 190 else 0)
		playerGui:SetAttribute(
			"RoleplayOSReservedBottomCentrePixels",
			if self.vehicleMode then 150 else 0
		)
	end
	self.context.Events.VehicleModeChanged:Fire(self.vehicleMode)
end

function VehicleUIController:_set(enabled: boolean)
	if self.vehicleMode == enabled then
		return
	end
	self.vehicleMode = enabled
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
			self:_set(active and seatPart ~= nil and seatPart:IsA("VehicleSeat"))
		end)
	)
	table.insert(
		self.connections,
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			local seatPart = humanoid.SeatPart
			self:_set(seatPart ~= nil and seatPart:IsA("VehicleSeat"))
		end)
	)
	self:_set(humanoid.SeatPart ~= nil and humanoid.SeatPart:IsA("VehicleSeat"))
end

function VehicleUIController:Start()
	local player = Players.LocalPlayer
	self:_broadcast()
	if player.Character then
		self:_watchCharacter(player.Character)
	end
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			self:_set(false)
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
