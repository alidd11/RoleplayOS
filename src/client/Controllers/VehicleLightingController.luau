--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- The driver's controls for road lighting.
--
-- Replaces the LocalScript the bought kit shipped inside every vehicle. That one
-- fired an unvalidated RemoteEvent parented to the car, which any player on the
-- server could fire for any vehicle; this goes through the framework's network
-- layer, which validates the payload, rate limits it, and checks server-side
-- that the sender is actually the driver.
--
-- The keys are deliberately the ones the kit used, because they are the ones
-- anybody who has driven these cars already knows.
local VehicleLightingController = { connections = {} }

local BINDINGS = {
	[Enum.KeyCode.Z] = "IndicateLeft",
	[Enum.KeyCode.C] = "IndicateRight",
	[Enum.KeyCode.X] = "Hazards",
	[Enum.KeyCode.L] = "Stage",
	-- Gamepad, matching the kit's shoulder buttons.
	[Enum.KeyCode.ButtonL1] = "IndicateLeft",
	[Enum.KeyCode.ButtonR1] = "IndicateRight",
	[Enum.KeyCode.ButtonX] = "Stage",
}

function VehicleLightingController:Init(context: any)
	self.context = context
end

function VehicleLightingController:_driving(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.SeatPart:IsA("VehicleSeat")
end

function VehicleLightingController:Start()
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			-- Never while the player is typing. The kit checked this too; it is the
			-- difference between indicating and putting a Z in the chat box.
			if processed then
				return
			end
			local action = BINDINGS[input.KeyCode]
			if not action or not self:_driving() then
				return
			end
			self.context.Controllers.NetworkController:Request("SetVehicleLights", {
				Action = action,
			})
		end)
	)
end

function VehicleLightingController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return VehicleLightingController
