--!strict

-- Replaces Roblox's own Tab player list.
--
-- The stock list shows Roblox usernames, which is exactly the identity this
-- game spends the rest of its client hiding behind characters and duty roles.
-- This one groups by Team and reads RoleplayOSDisplayName, the character name
-- CharacterService:Select puts on the Player instance - a Player attribute
-- replicates to every client on its own, so the roster needs no remote of its
-- own to stay current. Docked to the same top-right corner as the stock list,
-- narrow and translucent rather than a centred dialog, since that shape is
-- what makes it read as a Tab overlay and not another menu screen.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local DesignTokens = require(script.Parent.Parent.UI.DesignTokens)

local WIDTH = 230
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

	-- No shell radius, no stroke, no centred dialog frame: the stock list is a
	-- thin translucent column docked to the corner, not a panel, and dressing
	-- it up as one is what would have made it read as a menu instead of an
	-- overlay.
	local panel = Instance.new("Frame")
	panel.Name = "Roster"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Size = UDim2.fromOffset(WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	self.gui, self.panel = gui, panel
end

-- One thin translucent header per team, sorted alphabetically so the same
-- list does not reshuffle itself between openings, then its players as plain
-- rows underneath - the same two-tier shape the stock list uses.
--
-- Built fresh on every open rather than kept live while closed. A Tab list is
-- glanced at, not watched, and a roster that is current the moment it is
-- opened is all that ever gets asked of it - which is simpler and cannot go
-- stale while the panel sits hidden.
function PlayerListController:_rebuild()
	self.panel:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = self.panel

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
		header.Size = UDim2.fromOffset(WIDTH, 22)
		header.BackgroundColor3 = C.surface
		header.BackgroundTransparency = 0.35
		header.BorderSizePixel = 0
		header.Parent = self.panel
		local headerLabel = label(header, string.upper(teamName), DesignTokens.Text.dense, C.muted)
		headerLabel.Font = DesignTokens.Font.bold
		headerLabel.Position = UDim2.fromOffset(8, 0)
		headerLabel.Size = UDim2.new(1, -8, 1, 0)

		local players = byTeam[teamName]
		table.sort(players, function(a, b)
			return (a:GetAttribute("RoleplayOSDisplayName") or a.DisplayName)
				< (b:GetAttribute("RoleplayOSDisplayName") or b.DisplayName)
		end)
		for _, player in players do
			order += 1
			local row = Instance.new("Frame")
			row.LayoutOrder = order
			row.Size = UDim2.fromOffset(WIDTH, 24)
			row.BackgroundColor3 = C.canvas
			row.BackgroundTransparency = 0.45
			row.BorderSizePixel = 0
			row.Parent = self.panel
			local name = label(
				row,
				tostring(player:GetAttribute("RoleplayOSDisplayName") or player.DisplayName),
				DesignTokens.Text.dense,
				if player == Players.LocalPlayer then C.accent else C.text
			)
			name.Position = UDim2.fromOffset(14, 0)
			name.Size = UDim2.new(1, -22, 1, 0)
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
	-- Docked in the same corner the stock list used, just under the native
	-- control band, and clear of the Controls launcher's own reserve so
	-- neither one drifts under the other on a narrow screen.
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("PlayerList", function(layout)
		self.panel.Position = UDim2.new(1, -layout.RightReserve, 0, layout.NativeTop + 8)
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
