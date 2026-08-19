--!strict
local Players = game:GetService("Players")
local Tokens = require(script.Parent.Parent.Parent.UI.DesignTokens)
local C, T, S = Tokens.Colour, Tokens.Text, Tokens.Stroke

local Utils = {
	Tokens = Tokens,
	Colour = C,
	Text = T,
	Stroke = S,
}

local function formatTime(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(clamped / 60), clamped % 60)
end

local function text(
	parent: Instance,
	value: string,
	size: number,
	colour: Color3,
	bold: boolean?
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Tokens.Font.bold else Tokens.Font.regular
	item.Text = value
	item.TextColor3 = colour
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end

local function button(parent: Instance, value: string, fill: Color3): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = fill
	item.BorderSizePixel = 0
	item.Font = Tokens.Font.bold
	item.Text = value
	item.TextColor3 = C.text
	item.TextSize = T.button
	item.Parent = parent
	return item
end

local function outline(parent: Instance, colour: Color3?): UIStroke
	local item = Instance.new("UIStroke")
	item.Color = colour or C.border
	item.Thickness = S.thickness
	item.Transparency = S.transparency
	item.Parent = parent
	return item
end

local function distanceTo(player: Player): number?
	local localCharacter = Players.LocalPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not localRoot or not root or not localRoot:IsA("BasePart") or not root:IsA("BasePart") then
		return nil
	end
	return math.floor((localRoot.Position - root.Position).Magnitude + 0.5)
end

Utils.formatTime = formatTime
Utils.text = text
Utils.button = button
Utils.outline = outline
Utils.distanceTo = distanceTo

return Utils
