--!strict

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Coalescer = require(ReplicatedStorage.RoleplayOS.Shared.Coalescer)
local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

local MDTController = { connections = {} }
local MDT_ACTION = "RoleplayOSToggleMDT"

-- The map shares GetDispatchSnapshot with the dispatch board on this same
-- client, so it takes half of that endpoint's one-per-second refill.
local MAP_REFRESH_INTERVAL = 2
-- The incident list is the tight one. MDTGetIncidents refills at a quarter per
-- second, so four dispatch changes in a row would empty it for sixteen seconds
-- and refuse the officer's own searches for the rest of them. This leaves most
-- of the bucket to the officer and still keeps the list current.
local INCIDENT_REFRESH_INTERVAL = 6

local function radioBottom(layout: any): number
	local panel = Config.RadioPanel
	local footprint = if layout.Compact then panel.CompactFootprint else panel.Footprint
	return panel.Margin + footprint.Y + panel.Clearance
end

local PanelChrome = require(script.PanelChrome)
local Home = require(script.Home)
local Records = require(script.Records)

PanelChrome(MDTController)
Home(MDTController)
Records(MDTController)

function MDTController:Init(context: any)
	self.context = context
	self.recordType = "Home"
	self.allowed = false
	self.canWriteWarrants = false
	self.selectedRecord = nil
end

function MDTController:Start()
	self:_mount()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(
		self.connections,
		playerGui:GetAttributeChangedSignal("RoleplayOSCCTVOpen"):Connect(function()
			if playerGui:GetAttribute("RoleplayOSCCTVOpen") == true and self.shell.Visible then
				self.setOpen(false)
			end
		end)
	)
	local function updateShortcutLabel(lastInputType: Enum.UserInputType)
		if tostring(lastInputType):find("Gamepad") then
			local key = UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonSelect)
			local image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonSelect)
			self.launcher.Text = if image == ""
				then "MDT  ·  " .. (if key == "" then "VIEW" else key)
				else "MDT"
			self.shortcutGlyph.Image = image
			self.shortcutGlyph.Visible = image ~= ""
		else
			self.launcher.Text = "MDT  ·  M"
			self.shortcutGlyph.Visible = false
		end
	end
	local function toggleMDT(
		_actionName: string,
		inputState: Enum.UserInputState,
		inputObject: InputObject
	): Enum.ContextActionResult
		if
			inputState == Enum.UserInputState.Begin
			and inputObject.KeyCode == Enum.KeyCode.ButtonB
		then
			if self.warrantModal.Visible then
				self.warrantModal.Visible = false
				GuiService.SelectedObject = self.warrantAction
				return Enum.ContextActionResult.Sink
			elseif self.shell.Visible then
				self.setOpen(false)
				GuiService.SelectedObject = self.launcher
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end
		if
			inputState ~= Enum.UserInputState.Begin
			or not self.allowed
			or UserInputService:GetFocusedTextBox() ~= nil
		then
			return Enum.ContextActionResult.Pass
		end
		self.setOpen(not self.shell.Visible)
		if self.shell.Visible and UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.close
		elseif
			GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.shell)
		then
			GuiService.SelectedObject = self.launcher
		end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction(
		MDT_ACTION,
		toggleMDT,
		false,
		Enum.KeyCode.M,
		Enum.KeyCode.ButtonSelect,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle(MDT_ACTION, "MDT")
	ContextActionService:SetDescription(MDT_ACTION, "Open or close the data terminal.")
	updateShortcutLabel(UserInputService:GetLastInputType())
	table.insert(
		self.connections,
		UserInputService.LastInputTypeChanged:Connect(updateShortcutLabel)
	)
	local watchedTools = {}
	local function watchTool(tool: Instance)
		if
			not tool:IsA("Tool")
			or (tool.Name ~= "MDT" and tool:GetAttribute("RoleplayOSToolId") ~= "MDT")
			or watchedTools[tool]
		then
			return
		end
		watchedTools[tool] = true
		local function open()
			if self.allowed then
				self.setOpen(true)
			end
		end
		table.insert(self.connections, tool.Equipped:Connect(open))
		table.insert(self.connections, tool.Activated:Connect(open))
		table.insert(
			self.connections,
			tool.Unequipped:Connect(function()
				self.setOpen(false)
			end)
		)
	end
	local backpack = Players.LocalPlayer:WaitForChild("Backpack")
	for _, item in backpack:GetChildren() do
		watchTool(item)
	end
	table.insert(self.connections, backpack.ChildAdded:Connect(watchTool))
	table.insert(
		self.connections,
		Players.LocalPlayer.CharacterAdded:Connect(function(character)
			table.insert(self.connections, character.ChildAdded:Connect(watchTool))
		end)
	)
	-- Only the refreshes the server triggers are coalesced. An officer typing a
	-- search or switching tabs still goes straight out, because that is the
	-- player asking rather than dispatch telling.
	self.incidentRefresh = Coalescer.new(INCIDENT_REFRESH_INTERVAL, function()
		self:_performSearch()
	end)
	self.mapRefresh = Coalescer.new(MAP_REFRESH_INTERVAL, function()
		self:RefreshMap()
	end)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function()
			self:RefreshAccess()
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.DispatchChanged.Event:Connect(function(update)
			if not self.allowed then
				return
			end
			if update.Kind == "CallCreated" then
				self.context.Controllers.NotificationController:Show(
					"A new relevant dispatch call is available in MDT incidents.",
					"MDT update"
				)
			end
			if self.recordType == "Incident" and self.shell.Visible then
				self.incidentRefresh:Request()
			end
		end)
	)
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("MDT", function(layout)
		-- While driving the minimap moves to the left edge and the needs bars to
		-- the bottom left, so the launcher stacks directly beneath the minimap
		-- rather than sharing either position. The offset is derived from the
		-- minimap's own height so the two cannot drift into each other.
		-- Derived from the minimap's own configured footprint rather than a copy
		-- of its numbers, so resizing that panel moves this out of the way too.
		local minimap = Config.Minimap
		local minimapBottom = minimap.VehicleAnchorY
			+ (minimap.CompactPanelSize.Y / 2 * layout.HudScale)
				/ math.max(layout.Viewport.Y, 1)
		self.launcher.AnchorPoint = Vector2.new(0, 0)
		self.launcher.Position = if layout.Vehicle
			then UDim2.new(0, 18, minimapBottom, 12)
			-- On foot, keep the persistent terminal affordance in the same safe
			-- top-left rail as the radio instead of placing it at a fixed fraction
			-- of the viewport. That fixed 62% position was effectively invisible on
			-- tall displays and looked like the MDT had not been issued.
			-- Below the radio, not on top of it.
			--
			-- This sat at a fixed 58 down the left rail, which is inside the radio
			-- panel and over its content -- and the MDT's DisplayOrder is the higher
			-- of the two, so the button won and an officer on foot saw it across the
			-- radio the whole time. It now clears the radio's own footprint, read
			-- from the same config the radio lays itself out from.
			--
			-- NativeTop is gone as well. This ScreenGui is mounted with
			-- CoreUISafeInsets, so its origin is already below the top bar, and
			-- adding it again applied the bar twice and pushed the launcher about
			-- fifty pixels lower than intended. RadioController and
			-- CustodyController both carry a note about having fixed exactly this;
			-- the MDT was the one still doing it.
			else UDim2.fromOffset(18, radioBottom(layout))
		-- The shell never shrinks below its minimum size, so it is scaled against
		-- the usable area on every device class. Measuring the raw viewport
		-- instead let the terminal spill under the top bar and device cutouts.
		self.scale.Scale =
			self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(720, 470), 24)
		-- Closed on getting into a vehicle, not on every layout publish.
		--
		-- This ran on each publish, and the orchestrator publishes whenever the
		-- last input type changes, which on a mouse is constantly. Pressing M in a
		-- car reopened the terminal and the next mouse movement shut it again, so
		-- an officer could not re-read the call they were driving to. Closing it
		-- once on the way in keeps the windscreen clear without making the
		-- terminal unusable for the whole journey.
		if layout.Vehicle ~= self.inVehicle then
			self.inVehicle = layout.Vehicle
			if layout.Vehicle then
				self.setOpen(false)
			end
		end
	end)
	-- Dispatch pushes a change event whenever a call or unit moves state, so the
	-- map follows the live picture without polling.
	table.insert(
		self.connections,
		self.context.Events.DispatchChanged.Event:Connect(function()
			if self.shell.Visible then
				self.mapRefresh:Request()
			end
		end)
	)
	self:RefreshAccess()
end

function MDTController:Search(recordType: string, query: string, page: number?): any
	return self.context.Controllers.NetworkController:Request(
		"MDTSearch",
		{ Type = recordType, Query = query, Page = page or 1 }
	)
end

function MDTController:Destroy()
	ContextActionService:UnbindAction(MDT_ACTION)
	if self.incidentRefresh then
		self.incidentRefresh:Cancel()
	end
	if self.mapRefresh then
		self.mapRefresh:Cancel()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.map then
		self.map:Destroy()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return MDTController
