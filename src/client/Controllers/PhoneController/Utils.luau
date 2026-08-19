--!strict

local TweenService = game:GetService("TweenService")

local DESIGN = Vector2.new(326, 610)
local C = {
	Body = Color3.fromRGB(9, 12, 18),
	Screen = Color3.fromRGB(18, 24, 35),
	Card = Color3.fromRGB(30, 39, 54),
	Text = Color3.fromRGB(247, 249, 253),
	Muted = Color3.fromRGB(158, 171, 191),
	Blue = Color3.fromRGB(77, 151, 255),
	Green = Color3.fromRGB(53, 199, 111),
	Red = Color3.fromRGB(239, 75, 86),
}

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function label(parent: Instance, value: string, size: number, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = size
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

local function button(parent: Instance, value: string, colour: Color3?): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = colour or C.Card
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = 11
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Center
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	corner(item, 10)
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

local function input(parent: Instance, placeholder: string, multiline: boolean?): TextBox
	local item = Instance.new("TextBox")
	item.BackgroundColor3 = C.Card
	item.BorderSizePixel = 0
	item.ClearTextOnFocus = false
	item.Font = Enum.Font.Gotham
	item.MultiLine = multiline == true
	item.PlaceholderText = placeholder
	item.PlaceholderColor3 = C.Muted
	item.Text = ""
	item.TextColor3 = C.Text
	item.TextSize = 12
	item.TextWrapped = multiline == true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = if multiline then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	item.Parent = parent
	corner(item, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 10)
	pad.Parent = item
	return item
end

local function money(value: any): string
	local amount = math.floor(tonumber(value) or 0)
	local formatted = tostring(math.abs(amount))
	while true do
		local changed
		formatted, changed = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
		if changed == 0 then
			break
		end
	end
	return (if amount < 0 then "-£" else "£") .. formatted
end

local Utils = {
	C = C,
	DESIGN = DESIGN,
	corner = corner,
	label = label,
	button = button,
	input = input,
	money = money,
}

return Utils
