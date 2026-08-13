--!strict

-- Touch actions for vehicle packages whose original controls only expose keys.
-- The imported chassis remains authoritative; this controller only publishes
-- the same action as a short-lived attribute that the package can consume.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

local VehicleActionsController = { connections = {} }

local ACTIONS = {
	{
		Id = "Wheelie",
		Label = "WHEELIE",
		DefinitionIds = { HondaADV160 = true },
		Attribute = "RoleplayOSWheelieInput",
		Colour = Color3.fromRGB(38, 88, 142),
	},
}

local function button(parent: Instance, action: any): TextButton
	local item = Instance.new("TextButton")
	item.Name = action.Id
	item.AutoButtonColor = false
	item.BackgroundColor3 = action.Colour
	item.BackgroundTransparency = 0.12
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = action.Label
	item.TextColor3 = Color3.fromRGB(242, 247, 252)
	item.TextSize = 12
	item.TextWrapped = true
	item.Visible = false
	item.Parent = parent
	Instance.new("UICorner", item).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(116, 163, 207)
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.Parent = item
	return item
end

function VehicleActionsController:Init(context: any)
	self.context = context
	self.settings = Config.DrivingControls
	self.active = {}
	self.held = {}
end

function VehicleActionsController:_seat(): VehicleSeat?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return if seat and seat:IsA("VehicleSeat") and seat.Occupant == humanoid then seat else nil
end

function VehicleActionsController:_vehicle(): Model?
	local seat = self:_seat()
	return seat and seat:FindFirstAncestorOfClass("Model") or nil
end

function VehicleActionsController:_supports(vehicle: Model, action: any): boolean
	local definition = vehicle:GetAttribute("RoleplayOSDefinitionId")
	if type(definition) == "string" and action.DefinitionIds[definition] then
		return true
	end
	return false
end

function VehicleActionsController:_set(action: any, active: boolean)
	local vehicle = self:_vehicle()
	if vehicle and self:_supports(vehicle, action) then
		vehicle:SetAttribute(action.Attribute, active)
	end
	self.held[action.Id] = active
	local item = self.buttons[action.Id]
	if item then
		item.BackgroundTransparency = if active then 0 else 0.12
	end
end

function VehicleActionsController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSVehicleActions"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 13
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	self.buttons = {}
	for _, action in ACTIONS do
		local item = button(gui, action)
		self.buttons[action.Id] = item
		table.insert(
			self.connections,
			item.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1
				then
					self:_set(action, true)
				end
			end)
		)
		table.insert(
			self.connections,
			item.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1
				then
					self:_set(action, false)
				end
			end)
		)
	end
end

function VehicleActionsController:Start()
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind(
		"VehicleActions",
		function(layout)
			local vehicle = self:_vehicle()
			local shown = layout.InputMode == "Touch"
				and layout.State == "Driver"
				and vehicle ~= nil
			local index = 0
			for _, action in ACTIONS do
				local item = self.buttons[action.Id]
				local available = shown and vehicle and self:_supports(vehicle, action)
				item.Visible = available == true
				if available then
					index += 1
					local size = math.clamp(math.floor(72 * layout.HudScale), 58, 86)
					item.Size = UDim2.fromOffset(size, size)
					item.AnchorPoint = Vector2.new(1, 1)
					item.Position = UDim2.new(
						1,
						-(layout.SafeRight + 18),
						1,
						-(layout.SafeBottom + 116 + (index - 1) * (size + 10))
					)
				end
			end
		end
	)
	table.insert(
		self.connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			for _, action in ACTIONS do
				self:_set(action, false)
			end
		end)
	)
end

function VehicleActionsController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return VehicleActionsController
