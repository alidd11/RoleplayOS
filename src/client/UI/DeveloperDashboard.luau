--!strict

local Players = game:GetService("Players")
local Dashboard = {}

local function label(parent: Instance, text: string, height: number, colour: Color3?): TextLabel
	local item = Instance.new("TextLabel")
	item.Size = UDim2.new(1, 0, 0, height)
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.Gotham
	item.TextSize = 15
	item.TextColor3 = colour or Color3.fromRGB(210, 218, 232)
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextWrapped = true
	item.Text = text
	item.Parent = parent
	return item
end

function Dashboard.mount(context: any): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSDeveloperDashboard"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 24, 0.5, 0)
	panel.Size = UDim2.fromOffset(410, 470)
	panel.BackgroundColor3 = Color3.fromRGB(15, 20, 31)
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(49, 63, 88)
	stroke.Transparency = 0.2
	stroke.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 22)
	padding.PaddingBottom = UDim.new(0, 22)
	padding.PaddingLeft = UDim.new(0, 22)
	padding.PaddingRight = UDim.new(0, 22)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = panel

	local title = label(panel, "ROLEPLAYOS", 34, Color3.fromRGB(100, 176, 255))
	title.Font = Enum.Font.GothamBold
	title.TextSize = 27
	label(panel, "v0.1 engineering foundation · live Rojo sync", 24, Color3.fromRGB(143, 155, 177))
	local status = label(panel, "Connecting to server…", 48, Color3.fromRGB(255, 199, 92))
	local community = label(panel, "Community: loading", 42)
	label(panel, "ACTIVE FOUNDATIONS", 25, Color3.fromRGB(143, 155, 177)).Font =
		Enum.Font.GothamBold
	local capabilities = label(panel, "", 205)

	local response = context.Controllers.NetworkController:Request("GetFrameworkStatus", {})
	if response.Success then
		local data = response.Data
		status.Text = string.format(
			"● ONLINE  ·  Schema %d  ·  %s server",
			data.SchemaVersion,
			data.Server.Kind
		)
		status.TextColor3 = Color3.fromRGB(93, 218, 147)
		community.Text = if data.Server.Community
			then "Community: " .. data.Server.Community.Name
			else "Community-ready: public server mode"
		local lines = {}
		for _, capability in data.Capabilities do
			table.insert(lines, "✓  " .. capability)
		end
		capabilities.Text = table.concat(lines, "\n")
	else
		status.Text = "● SERVER FOUNDATION UNAVAILABLE\n" .. response.Message
		status.TextColor3 = Color3.fromRGB(255, 112, 112)
	end

	return gui
end

return table.freeze(Dashboard)
