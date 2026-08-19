--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Utils = require(script.Parent.Utils)
local C = Utils.Colour
local distanceToTarget = Utils.distanceToTarget

local INTERACTION_RANGE = 12

return function(PublicSafetyController)
	function PublicSafetyController:_targetUserId(): number?
		local mouse = Players.LocalPlayer:GetMouse()
		local model = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")
		local player = model and Players:GetPlayerFromCharacter(model)
		if player and player ~= Players.LocalPlayer then
			return player.UserId
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return nil
		end
		local viewport = camera.ViewportSize
		local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local localCharacter = Players.LocalPlayer.Character
		params.FilterDescendantsInstances = if localCharacter then { localCharacter } else {}
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 24, params)
		local hitModel = hit and hit.Instance:FindFirstAncestorOfClass("Model")
		local hitPlayer = hitModel and Players:GetPlayerFromCharacter(hitModel)
		return if hitPlayer and hitPlayer ~= Players.LocalPlayer then hitPlayer.UserId else nil
	end

	function PublicSafetyController:_setActionsOpen(open: boolean)
		self.actionPanel.Visible = open
		self.actionGeneration = (self.actionGeneration or 0) + 1
		if open then
			self.previousSelection = GuiService.SelectedObject
			if UserInputService.GamepadEnabled then
				GuiService.SelectedObject = self.actionClose
			end
			self:_startActionRefresh()
			return
		end
		self.actionTargetUserId = nil
		table.clear(self.actionState)
		if
			GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.actionPanel)
		then
			local previous = self.previousSelection
			GuiService.SelectedObject = if previous and previous.Parent then previous else nil
		end
	end

	function PublicSafetyController:_showActions(targetUserId: number, state: any?)
		self.actionTargetUserId = targetUserId
		table.clear(self.actionState)
		if type(state) == "table" then
			for key, value in state do
				self.actionState[key] = value
			end
		end
		self.searchResult.Text = ""
		self:_setActionsOpen(true)
		self:_refreshActions()
	end

	-- Everything the officer needs to know before pressing anything: who they are
	-- holding, what has already been done to them, and how far away they are.
	--
	-- The panel used to state only the name. Whether the caution had been read,
	-- whether a search had been recorded and whether the officer still had hold of
	-- them were all facts the server tracked and the officer had no way to see, so
	-- the workflow was carried out from memory and the buttons gave no clue which
	-- of them had already been used.
	function PublicSafetyController:_refreshActions()
		local userId = self.actionTargetUserId
		local target = if userId then Players:GetPlayerByUserId(userId) else nil
		if not target then
			self.actionTarget.Text = "DETAINEE  ·  NO LONGER HERE"
			self.actionStatus.Text = ""
			self.actionRange.Text = ""
			return
		end
		self.actionTarget.Text = string.format("%s  ·  @%s", target.DisplayName, target.Name)

		-- The reply to CuffPlayer beats the detainee's replicated attribute to this
		-- client, so for the first moments after an arrest the panel is trusting the
		-- answer it already has rather than reporting the person it just cuffed as
		-- not cuffed.
		local cuffed = target:GetAttribute("RoleplayOSCuffed") == true
			or (not self.actionCuffedSeen and self.actionState.Cuffed == true)
		local escorted = target:GetAttribute("RoleplayOSEscorted") == true
		local position = tostring(target:GetAttribute("RoleplayOSCuffPosition") or "Rear")
		local held = escorted and self.actionState.EscortedByUserId == Players.LocalPlayer.UserId
		local parts = {}
		table.insert(parts, if cuffed then "CUFFED " .. string.upper(position) else "NOT CUFFED")
		if escorted then
			table.insert(parts, if held then "YOU HAVE HOLD" else "HELD BY ANOTHER OFFICER")
		end
		if self.actionState.Cautioned then
			table.insert(parts, "CAUTIONED")
		end
		if self.actionState.Searched then
			table.insert(parts, "SEARCHED")
		end
		self.actionStatus.Text = table.concat(parts, "   ·   ")
		self.actionStatus.TextColor3 = if cuffed then C.accent else C.warning

		local metres = distanceToTarget(userId)
		if not metres then
			self.actionRange.Text = "OUT OF SIGHT"
			self.actionRange.TextColor3 = C.warning
		elseif metres > INTERACTION_RANGE then
			self.actionRange.Text = string.format("%d M AWAY  ·  TOO FAR, WALK CLOSER", metres)
			self.actionRange.TextColor3 = C.warning
		else
			self.actionRange.Text = string.format("%d M AWAY  ·  IN REACH", metres)
			self.actionRange.TextColor3 = C.muted
		end

		self.escort.Text = if held
			then "LET GO"
			elseif escorted then "HELD BY OTHER"
			else "TAKE HOLD"
	end

	-- Distance changes with every step and the cuffs can come off from the other
	-- officer's panel, so the readout is re-derived on a timer from replicated
	-- attributes. No request is made: everything on it is already on the client.
	function PublicSafetyController:_startActionRefresh()
		local generation = self.actionGeneration
		self.actionCuffedSeen = false
		task.spawn(function()
			local opened = os.clock()
			while self.actionGeneration == generation and self.actionPanel.Visible do
				local userId = self.actionTargetUserId
				local target = if userId then Players:GetPlayerByUserId(userId) else nil
				if target and target:GetAttribute("RoleplayOSCuffed") == true then
					self.actionCuffedSeen = true
				end
				self:_refreshActions()
				-- The panel describes a person in handcuffs in front of the officer, and
				-- closes when that stops being true rather than staying up over a
				-- workflow that has already ended somewhere else. It waits to have seen
				-- the cuffs replicate before it will act on their absence, because
				-- otherwise the arrest that opened it would close it a frame later.
				local uncuffed = self.actionCuffedSeen
					and (not target or target:GetAttribute("RoleplayOSCuffed") ~= true)
				local neverArrived = not self.actionCuffedSeen and os.clock() - opened > 5
				if not target or uncuffed or neverArrived then
					self:_setActionsOpen(false)
					return
				end
				task.wait(0.4)
			end
		end)
	end

	-- What actually happened, rather than "Custody action completed" for every
	-- button on the panel and "Custody action was refused" for every possible reason.
	function PublicSafetyController:_describe(action: string, data: any): string
		local state = if type(data) == "table" and type(data.State) == "table"
			then data.State
			else data
		if action == "Caution" then
			return "Caution read out."
		elseif action == "Search" then
			local items = if type(data) == "table" and type(data.Items) == "table"
				then data.Items
				else {}
			return if #items > 0
				then "Search recorded. Found: " .. table.concat(items, ", ") .. "."
				else "Search recorded. They were carrying nothing."
		elseif action == "SeizeWeapons" then
			local weapons = if type(data) == "table" and type(data.Weapons) == "table"
				then data.Weapons
				else {}
			return if #weapons > 0
				then "Seized: " .. table.concat(weapons, ", ") .. "."
				else "Nothing to seize. They were carrying no weapons."
		elseif action == "Escort" then
			local held = type(state) == "table"
				and state.EscortedByUserId == Players.LocalPlayer.UserId
			return if held then "You have hold of them." else "You have let go of them."
		elseif action == "Vehicle" then
			return "Moved into or out of the nearest custody seat."
		elseif action == "CuffPosition" then
			local position = if type(state) == "table" then tostring(state.CuffPosition) else "Rear"
			return "Cuffs moved to the " .. string.lower(position) .. "."
		elseif action == "Release" then
			return "Handcuffs removed. They are free to go."
		end
		return "Done."
	end

	function PublicSafetyController:_custodyAction(action: string, data: any?)
		if not self.actionTargetUserId then
			self.context.Controllers.NotificationController:Show(
				"Nobody is selected. Use your handcuffs on somebody first.",
				"Custody"
			)
			return
		end
		local response = self.context.Controllers.NetworkController:Request("CustodyAction", {
			TargetUserId = self.actionTargetUserId,
			Action = action,
			Data = data or {},
		})
		if not response.Success then
			self.context.Controllers.NotificationController:Show(
				self.context.Controllers.CustodyController:Explain(
					response,
					"That custody action was refused."
				),
				"Custody",
				"Danger"
			)
			return
		end
		local state = if type(response.Data) == "table"
				and type(response.Data.State) == "table"
			then response.Data.State
			else response.Data
		if type(state) == "table" and state.Cuffed ~= nil then
			for key, value in state do
				self.actionState[key] = value
			end
		end
		if action == "Search" then
			local items = if type(response.Data.Items) == "table" then response.Data.Items else {}
			self.searchResult.Text = if #items > 0
				then "FOUND  ·  " .. table.concat(items, ", ")
				else "FOUND  ·  NOTHING"
			self.searchResult.TextColor3 = if #items > 0 then C.warning else C.muted
		end
		self.context.Controllers.NotificationController:Show(
			self:_describe(action, response.Data),
			"Custody",
			"Success"
		)
		if action == "Release" then
			self:_setActionsOpen(false)
			return
		end
		self:_refreshActions()
	end
end
