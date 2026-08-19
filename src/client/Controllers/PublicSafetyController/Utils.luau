--!strict
local Players = game:GetService("Players")
local Tokens = require(script.Parent.Parent.Parent.UI.DesignTokens)

local Utils = {
	Tokens = Tokens,
	Colour = Tokens.Colour,
	Text = Tokens.Text,
	Stroke = Tokens.Stroke,
}
local C, T = Utils.Colour, Utils.Text

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function label(
	parent: Instance,
	y: number,
	height: number,
	textSize: number,
	bold: boolean
): TextLabel
	local item = Instance.new("TextLabel")
	item.Position = UDim2.fromOffset(174, y)
	item.Size = UDim2.new(1, -194, 0, height)
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.TextColor3 = Color3.fromRGB(30, 40, 48)
	item.TextSize = textSize
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

local function actionButton(parent: Instance, value: string, fill: Color3?): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.Size = UDim2.new(0.5, -5, 0, 38)
	item.BackgroundColor3 = fill or C.raised
	item.BorderSizePixel = 0
	item.Font = Tokens.Font.bold
	item.Text = value
	item.TextColor3 = C.text
	item.TextSize = T.button
	item.Parent = parent
	return item
end

local function panelLabel(
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

local function distanceToTarget(userId: number?): number?
	local target = if userId then Players:GetPlayerByUserId(userId) else nil
	local localCharacter = Players.LocalPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not localRoot or not root or not localRoot:IsA("BasePart") or not root:IsA("BasePart") then
		return nil
	end
	return math.floor((localRoot.Position - root.Position).Magnitude + 0.5)
end

Utils.corner = corner
Utils.label = label
Utils.actionButton = actionButton
Utils.panelLabel = panelLabel
Utils.distanceToTarget = distanceToTarget

return Utils
