--!strict
return function(PublicSafetyController)
	function PublicSafetyController:_watchTool(tool: Tool)
		if self.watched[tool] then
			return
		end
		local roleplayToolId = tostring(tool:GetAttribute("RoleplayOSToolId") or tool.Name)
		if
			roleplayToolId ~= "Handcuffs"
			and roleplayToolId ~= "ID Card"
			and roleplayToolId ~= "Warrant Card"
		then
			return
		end
		self.watched[tool] = true
		table.insert(
			self.connections,
			tool.Activated:Connect(function()
				local target = self:_targetUserId()
				if not target then
					self.context.Controllers.NotificationController:Show(
						"Point at a player standing near you and use it again.",
						tool.Name
					)
					return
				end
				local isCuffs = roleplayToolId == "Handcuffs"
				local response = self.context.Controllers.NetworkController:Request(
					if isCuffs then "CuffPlayer" else "GetPresentedId",
					if isCuffs
						then { TargetUserId = target, Mode = "Apply" }
						else {
							TargetUserId = target,
							CredentialType = if roleplayToolId == "Warrant Card"
								then "Police"
								else "Civilian",
						}
				)
				if not response.Success then
					-- The server sends one message for every refusal the handcuffs can
					-- meet -- wrong role, too far, target dead, cuffs not in hand -- and
					-- the officer was shown the same sentence for all of them.
					self.context.Controllers.NotificationController:Show(
						self.context.Controllers.CustodyController:Explain(
							response,
							"The handcuffs could not be used."
						),
						roleplayToolId,
						"Danger"
					)
					return
				end
				if not isCuffs then
					self.context.Controllers.NotificationController:Show(
						response.Message,
						roleplayToolId
					)
					return
				end
				if response.Data and response.Data.Cuffed then
					-- Also the way back in. Using the cuffs on somebody already wearing
					-- them reopens their custody actions, which is the only route back
					-- to the panel after the officer has closed it.
					self:_showActions(target, response.Data)
				end
			end)
		)
	end

	function PublicSafetyController:_scan(container: Instance, slot: string)
		for _, child in container:GetChildren() do
			if child:IsA("Tool") then
				self:_watchTool(child)
			end
		end
		-- Backpack and Character must be watched simultaneously. Replacing the
		-- global listener here used to make credentials issued after duty started
		-- visible but inert because scanning Character disconnected Backpack.
		local existing = self.scanConnections[slot]
		if existing then
			existing:Disconnect()
		end
		self.scanConnections[slot] = container.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				self:_watchTool(child)
			end
		end)
	end
end
