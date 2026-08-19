--!strict

local Utils = require(script.Parent.Utils)

local Tokens = Utils.Tokens
local C, R, T, S = Utils.C, Utils.R, Utils.T, Utils.S

return function(VehicleSpawnerController)
	function VehicleSpawnerController:_customPlate(
		spawnerId: string,
		vehicleId: string,
		current: string,
		onSaved: (string) -> ()
	)
		if not self.gui then
			return
		end
		local dialog = Instance.new("Frame")
		dialog.Name = "CustomRegistration"
		dialog.AnchorPoint = Vector2.new(0.5, 0.5)
		dialog.Position = UDim2.fromScale(0.5, 0.5)
		dialog.Size = UDim2.fromOffset(360, 220)
		dialog.BackgroundColor3 = Color3.fromRGB(13, 23, 36)
		dialog.BorderSizePixel = 0
		dialog.ZIndex = 20
		dialog.Parent = self.gui
		local constraint = Instance.new("UISizeConstraint")
		constraint.MinSize = Vector2.new(290, 210)
		constraint.MaxSize = Vector2.new(360, 220)
		constraint.Parent = dialog
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, R.panel)
		corner.Parent = dialog
		local stroke = Instance.new("UIStroke")
		stroke.Color = C.border
		stroke.Transparency = S.transparency
		stroke.Thickness = S.thickness
		stroke.Parent = dialog
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(20, 18)
		title.Size = UDim2.new(1, -40, 0, 28)
		title.Font = Enum.Font.GothamBold
		title.Text = "CUSTOM REGISTRATION"
		title.TextColor3 = C.text
		title.TextSize = T.title
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.ZIndex = 21
		title.Parent = dialog
		local input = Instance.new("TextBox")
		input.Position = UDim2.fromOffset(20, 61)
		input.Size = UDim2.new(1, -40, 0, 54)
		input.BackgroundColor3 = C.raised
		input.BorderSizePixel = 0
		input.ClearTextOnFocus = false
		input.Font = Tokens.Font.bold
		input.PlaceholderText = "AB12 CDE"
		input.Text = current
		input.TextColor3 = C.text
		input.PlaceholderColor3 = C.muted
		input.TextSize = 18
		input.TextYAlignment = Enum.TextYAlignment.Center
		input.ZIndex = 21
		input.Parent = dialog
		local inputCorner = Instance.new("UICorner")
		inputCorner.CornerRadius = UDim.new(0, R.control)
		inputCorner.Parent = input
		local cancel = Instance.new("TextButton")
		cancel.Position = UDim2.new(0, 20, 1, -64)
		cancel.Size = UDim2.new(0.5, -25, 0, 44)
		cancel.BackgroundColor3 = C.raised
		cancel.BorderSizePixel = 0
		cancel.Font = Tokens.Font.bold
		cancel.Text = "CANCEL"
		cancel.TextColor3 = C.text
		cancel.TextSize = T.button
		cancel.ZIndex = 21
		cancel.Parent = dialog
		local cancelCorner = Instance.new("UICorner")
		cancelCorner.CornerRadius = UDim.new(0, R.control)
		cancelCorner.Parent = cancel
		local save = cancel:Clone()
		save.Position = UDim2.new(0.5, 5, 1, -64)
		save.BackgroundColor3 = C.accentFill
		save.Text = "SAVE"
		save.Parent = dialog
		cancel.Activated:Connect(function()
			dialog:Destroy()
		end)
		save.Activated:Connect(function()
			save.Active = false
			save.Text = "CHECKING…"
			local response = self.context.Controllers.NetworkController:Request(
				"SetCustomVehicleRegistration",
				{ SpawnerId = spawnerId, VehicleId = vehicleId, Registration = input.Text }
			)
			self.context.Controllers.NotificationController:Show(response.Message, "Vehicles")
			if response.Success then
				local registration = tostring(response.Data.Registration)
				onSaved(registration)
				dialog:Destroy()
			else
				save.Active = true
				save.Text = "SAVE"
			end
		end)
		input:CaptureFocus()
	end

	-- Frames a preview model in a viewport, from the vehicle's own front three
	-- quarter. Shared by the grid card and the detail view so they cannot disagree
	-- about which way a car is pointing.
end
