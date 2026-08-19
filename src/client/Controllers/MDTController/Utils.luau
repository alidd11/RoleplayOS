--!strict

local TweenService = game:GetService("TweenService")
local TerminalTheme = require(script.Parent.Parent.Parent.UI.OperationalTerminalTheme)
local C = TerminalTheme

local Utils = {
	C = C,
}

local DEPARTMENT_UI = {
	Police = {
		Title = "FORCE CONTROL  ·  OPERATIONAL MDT",
		Subtitle = "POLICE CONTROL / INTELLIGENCE & DISPATCH  ·  RESTRICTED",
		Accent = Color3.fromRGB(72, 132, 224),
		Tiles = {
			{ "Incidents", "Review live calls, attending units and scene updates.", "Incident" },
			{ "People", "Search person records, warnings and warrants.", "Person" },
			{ "Vehicles", "Look up registrations, keepers and vehicle markers.", "Vehicle" },
			{ "Units & map", "See active units, incidents and locations.", "Map" },
		},
	},
	Ambulance = {
		Title = "AMBULANCE EOC  ·  OPERATIONAL CAD",
		Subtitle = "EMERGENCY OPERATIONS CENTRE / RESPONSE & HANDOVER  ·  RESTRICTED",
		Accent = Color3.fromRGB(74, 198, 139),
		Tiles = {
			{
				"Emergency calls",
				"Review triaged incidents and allocate response crews.",
				"Incident",
			},
			{
				"Patient records",
				"Search person details and relevant safety information.",
				"Person",
			},
			{ "Response vehicles", "Check vehicle details and operational markers.", "Vehicle" },
			{ "Crews & map", "Track response locations and multi-agency incidents.", "Map" },
		},
	},
	Fire = {
		Title = "FIRE CONTROL  ·  MOBILISING CAD",
		Subtitle = "FIRE CONTROL / APPLIANCE & INCIDENT MANAGEMENT  ·  RESTRICTED",
		Accent = Color3.fromRGB(235, 104, 76),
		Tiles = {
			{ "Mobilisations", "Review incidents and appliance attendance status.", "Incident" },
			{ "Risk information", "Search people and operational safety information.", "Person" },
			{ "Appliances", "Check vehicle details and response resources.", "Vehicle" },
			{ "Incident map", "Share locations and multi-agency situational awareness.", "Map" },
		},
	},
	Control = {
		Title = "JOINT CONTROL  ·  INCIDENT BOARD",
		Subtitle = "MULTI-AGENCY CONTROL / DISPATCH & INFORMATION SHARING  ·  RESTRICTED",
		Accent = Color3.fromRGB(50, 190, 188),
		Tiles = {
			{
				"Live incidents",
				"Create, assign and monitor active emergency calls.",
				"Incident",
			},
			{
				"Resolved CAD archive",
				"Review closed calls and retained incident records.",
				"Resolved",
			},
			{ "People records", "Search operational information shared with control.", "Person" },
			{ "Vehicles", "Check registrations, keepers and markers.", "Vehicle" },
			{ "Multi-agency map", "Coordinate units, incidents and partner activity.", "Map" },
		},
	},
}

local function departmentUI(departmentId: string?): any
	return DEPARTMENT_UI[departmentId or ""] or DEPARTMENT_UI.Control
end

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function text(parent: Instance, value: string, size: number, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

local function button(parent: Instance, value: string): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = C.Raised
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = 11
	item.Parent = parent
	corner(item, 8)
	local scale = Instance.new("UIScale")
	scale.Parent = item
	item.MouseButton1Down:Connect(function()
		TweenService
			:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 0.97,
			})
			:Play()
	end)
	item.MouseButton1Up:Connect(function()
		TweenService
			:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			:Play()
	end)
	return item
end

Utils.departmentUI = departmentUI
Utils.corner = corner
Utils.text = text
Utils.button = button

return Utils
