--!strict

-- Replaces Roblox's own Tab player list.
--
-- The stock list shows Roblox usernames, which is exactly the identity this
-- game spends the rest of its client hiding behind characters and duty roles.
-- This one groups by Team and reads RoleplayOSDisplayName, the character name
-- CharacterService:Select puts on the Player instance - a Player attribute
-- replicates to every client on its own, so the roster needs no remote of its
-- own to stay current.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local DesignTokens = require(script.Parent.Parent.UI.DesignTokens)

local DESIGN = Vector2.new(340, 460)
local ACTION = "RoleplayOSPlayerList"

local C = DesignTokens.Colour

local PlayerListController = { connections = {} }

function PlayerListController:Init(context: any)
	self.context = context
end

local function label(parent: Instance, text: string, size: number, colour: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = DesignTokens.Font.regular
	item.Text = text
	item.TextColor3 = colour
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

function PlayerListController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSPlayerList"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 40
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Roster"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	panel.BackgroundColor3 = C.surface
	panel.BorderSizePixel = 0
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, DesignTokens.Radius.shell)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.border
	stroke.Transparency = DesignTokens.Stroke.transparency
	stroke.Thickness = DesignTokens.Stroke.thickness
	stroke.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = label(panel, "PLAYERS", DesignTokens.Text.title, C.text)
	title.Font = DesignTokens.Font.bold
	title.Position = UDim2.fromOffset(20, 16)
	title.Size = UDim2.new(1, -40, 0, 24)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Roster"
	list.Position = UDim2.fromOffset(14, 54)
	list.Size = UDim2.new(1, -28, 1, -68)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = DesignTokens.Scroll.barThickness
	list.ScrollBarImageTransparency = DesignTokens.Scroll.barTransparency
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, DesignTokens.Spacing.gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	self.gui, self.panel, self.scale, self.list = gui, panel, scale, list
end

-- One header per team, sorted alphabetically so the same list does not
-- reshuffle itself between openings, then its players underneath.
--
-- Built fresh on every open rather than kept live while closed. A Tab list is
-- glanced at, not watched, and a roster that is current the moment it is
-- opened is all that ever gets asked of it - which is simpler and cannot go
-- stale while the panel sits hidden.
function PlayerListController:_rebuild()
	for _, child in self.list:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local byTeam: { [string]: { Player } } = {}
	local teamNames = {}
	for _, player in Players:GetPlayers() do
		local teamName = if player.Team then player.Team.Name else "Unassigned"
		if not byTeam[teamName] then
			byTeam[teamName] = {}
			table.insert(teamNames, teamName)
		end
		table.insert(byTeam[teamName], player)
	end
	table.sort(teamNames)

	local order = 0
	for _, teamName in teamNames do
		order += 1
		local header = Instance.new("Frame")
		header.Name = "Header_" .. teamName
		header.LayoutOrder = order
		header.Size = UDim2.new(1, 0, 0, 26)
		header.BackgroundTransparency = 1
		header.Parent = self.list
		local headerLabel =
			label(header, string.upper(teamName), DesignTokens.Text.section, C.muted)
		headerLabel.Font = DesignTokens.Font.bold
		headerLabel.Size = UDim2.fromScale(1, 1)

		local players = byTeam[teamName]
		table.sort(players, function(a, b)
			return (a:GetAttribute("RoleplayOSDisplayName") or a.DisplayName)
				< (b:GetAttribute("RoleplayOSDisplayName") or b.DisplayName)
		end)
		for _, player in players do
			order += 1
			local row = Instance.new("Frame")
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, 32)
			row.BackgroundColor3 = C.raised
			row.BorderSizePixel = 0
			row.Parent = self.list
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, DesignTokens.Radius.card)
			local name = label(
				row,
				tostring(player:GetAttribute("RoleplayOSDisplayName") or player.DisplayName),
				DesignTokens.Text.body,
				if player == Players.LocalPlayer then C.accent else C.text
			)
			name.Position = UDim2.fromOffset(12, 0)
			name.Size = UDim2.new(1, -24, 1, 0)
			name.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end
end

function PlayerListController:Open()
	if not self.gui then
		return
	end
	self:_rebuild()
	self.gui.Enabled = true
end

function PlayerListController:Close()
	if self.gui then
		self.gui.Enabled = false
	end
end

function PlayerListController:Toggle()
	if self.gui and self.gui.Enabled then
		self:Close()
	else
		self:Open()
	end
end

function PlayerListController:Start()
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("PlayerList", function(layout)
		self.scale.Scale = self.context.Controllers.UIOrchestrator:FitScale(layout, DESIGN, 40)
	end)
	-- Left disabled permanently rather than toggled alongside the start menu the
	-- way it used to be: this panel replaces it outright, so there is no state
	-- where the stock list should still be reachable.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	ContextActionService:BindAction(ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Tab, Enum.KeyCode.ButtonSelect)
end

function PlayerListController:Destroy()
	ContextActionService:UnbindAction(ACTION)
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

return PlayerListController
