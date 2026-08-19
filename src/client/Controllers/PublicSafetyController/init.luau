--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

-- Weak keyed. A tool destroyed on respawn should be collectable, and holding it
-- strongly kept every tool the player had ever carried alive for the session.
local PublicSafetyController = {
	connections = {},
	watched = setmetatable({}, { __mode = "k" }),
	scanConnections = {},
	actionState = {},
}

local CLOSE_ACTION = "RoleplayOSCustodyActionsClose"

local ActionsPanel = require(script.ActionsPanel)
local IdCard = require(script.IdCard)
local ToolWatch = require(script.ToolWatch)
local PanelUI = require(script.PanelUI)

-- Each of these attaches a group of methods onto PublicSafetyController
-- directly (they only need `self`, not a lexical upvalue) - the same split
-- used across this session. Order does not matter: nothing here runs until a
-- caller invokes a method, well after every group is attached.
ActionsPanel(PublicSafetyController)
IdCard(PublicSafetyController)
ToolWatch(PublicSafetyController)
PanelUI(PublicSafetyController)

function PublicSafetyController:Init(context: any)
	self.context = context
end

function PublicSafetyController:Start()
	self:_mount()
	local credentialEvent =
		self.context.Controllers.NetworkController:ResolveEvent("CredentialPresented")
	if credentialEvent then
		table.insert(
			self.connections,
			credentialEvent.OnClientEvent:Connect(function(card)
				if type(card) == "table" then
					self:_showCard(card)
				end
			end)
		)
	end
	-- CustodyService owns the chair's ProximityPrompt server-side and validates
	-- the trigger itself, so this is a read-only reply naming who is in the
	-- chair (or why there is nobody to process) rather than a request this
	-- client makes - the same shape VendorOpened already uses.
	--
	-- Goes straight to the booking terminal, not the roadside actions panel.
	-- Caution, search and the rest happen at the point of arrest and are still
	-- reached by using the cuffs again on a detainee stood in front of an
	-- officer; sitting someone down in a custody chair is specifically the
	-- booking-desk moment, and putting the same roadside panel behind it would
	-- have made the chair nothing but a second way to open the first screen.
	local chairEvent =
		self.context.Controllers.NetworkController:ResolveEvent("CustodyChairProcessed")
	if chairEvent then
		table.insert(
			self.connections,
			chairEvent.OnClientEvent:Connect(function(result)
				if type(result) ~= "table" then
					return
				end
				if result.Success and type(result.Data) == "table" then
					self.context.Controllers.CustodyController:Open(result.Data.TargetUserId)
					return
				end
				self.context.Controllers.NotificationController:Show(
					self.context.Controllers.CustodyController:Explain(
						{ Code = result.Reason },
						"That chair could not be used."
					),
					"Custody Chair",
					"Danger"
				)
			end)
		)
	end
	ContextActionService:BindAction(CLOSE_ACTION, function(_, state)
		if state ~= Enum.UserInputState.Begin or not self.actionPanel.Visible then
			return Enum.ContextActionResult.Pass
		end
		self:_setActionsOpen(false)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(CLOSE_ACTION, "Close custody actions")
	ContextActionService:SetDescription(
		CLOSE_ACTION,
		"Closes the restraint and custody action panel"
	)
	-- Stand the panel down when the thing it belongs to ends.
	--
	-- It closed on its own buttons, on Escape, and on nothing else, so going off
	-- duty, changing team or being killed mid-arrest left a full custody
	-- workflow on screen for a detainee the officer no longer had, every button
	-- of which the server would refuse.
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function()
			if self.actionPanel.Visible then
				self:_setActionsOpen(false)
			end
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.StartMenuChanged.Event:Connect(function()
			if self.actionPanel.Visible then
				self:_setActionsOpen(false)
			end
		end)
	)
	local player = Players.LocalPlayer
	table.insert(
		self.connections,
		player.CharacterRemoving:Connect(function()
			if self.actionPanel.Visible then
				self:_setActionsOpen(false)
			end
			self.card.Visible = false
		end)
	)
	self:_scan(player:WaitForChild("Backpack"), "Backpack")
	if player.Character then
		self:_scan(player.Character, "Character")
	end
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			self:_scan(character, "Character")
		end)
	)
end

function PublicSafetyController:Destroy()
	ContextActionService:UnbindAction(CLOSE_ACTION)
	-- Retires the status refresh loop as well: it is a spawned thread rather than
	-- a connection, so nothing else would stop it.
	self.actionGeneration = (self.actionGeneration or 0) + 1
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.scanConnections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.scanConnections)
	table.clear(self.actionState)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return PublicSafetyController
