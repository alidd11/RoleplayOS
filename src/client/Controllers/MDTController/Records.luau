--!strict

local Utils = require(script.Parent.Utils)
local C = Utils.C
local corner = Utils.corner
local text = Utils.text
local button = Utils.button
local departmentUI = Utils.departmentUI

return function(MDTController)
	function MDTController:_renderResults(items: { any })
		self.selectedRecord = nil
		self.warrantAction.Visible = false
		self.revokeAction.Visible = false
		for _, child in self.results:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		if #items == 0 then
			self.detailName.Text = "No matching records"
			self.detailMeta.Text =
				"Check the spelling or try a broader search. Searches require at least two characters."
		end
		for _, record in items do
			local row = button(self.results, "")
			row.BackgroundColor3 = C.Raised
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -5, 0, 62)
			row.Parent = self.results
			corner(row, 9)
			local primary = text(
				row,
				record.FullName or record.Registration or record.Title or "Unknown record",
				13,
				true
			)
			primary.Position = UDim2.fromOffset(14, 10)
			primary.Size = UDim2.new(1, -28, 0, 20)
			-- Names come from player records and have no length limit, so a long one
			-- ran on under the VIEW control at the end of its own row.
			primary.TextTruncate = Enum.TextTruncate.AtEnd
			local secondary = text(
				row,
				record.DateOfBirth and ("Date of birth  ·  " .. record.DateOfBirth)
					or record.Title and ("Incident  ·  " .. tostring(record.Status or "Unknown"))
					or ("Vehicle  ·  " .. tostring(record.DefinitionId or "Unknown")),
				10
			)
			secondary.Position = UDim2.fromOffset(14, 33)
			secondary.Size = UDim2.new(1, -28, 0, 18)
			secondary.TextTruncate = Enum.TextTruncate.AtEnd
			secondary.TextColor3 = C.Muted
			local open = text(row, "VIEW  ›", 9, true)
			open.AnchorPoint = Vector2.new(1, 0.5)
			open.Position = UDim2.new(1, -14, 0.5, 0)
			open.Size = UDim2.fromOffset(60, 18)
			open.TextXAlignment = Enum.TextXAlignment.Right
			open.TextColor3 = C.Accent
			row.Activated:Connect(function()
				self.selectedRecord = record
				self.warrantAction.Visible = record.FullName ~= nil and self.canWriteWarrants
				self.revokeAction.Visible = record.FullName ~= nil
					and self.canWriteWarrants
					and #(record.Warrants or {}) > 0
				self.revokeAction.Text = "REVOKE WARRANT"
				self.revokeConfirmationId = nil
				self.detailTitle.Text = if record.FullName
					then "PERSON RECORD"
					elseif record.Title then "INCIDENT RECORD"
					else "VEHICLE RECORD"
				self.detailName.Text = record.FullName
					or record.Registration
					or record.Title
					or "Unknown record"
				if record.FullName and record.AccessProfile == "Emergency" then
					self.detailMeta.Text = string.format(
						"DATE OF BIRTH\n%s\n\nACCESS PROFILE\nEmergency service identity view\n\nPolice, custody and driving-enforcement records are restricted.",
						tostring(record.DateOfBirth or "Not recorded")
					)
				elseif record.FullName and record.AccessProfile == "Highways" then
					local licences = {}
					for licenceId, value in record.Licences or {} do
						if value then
							table.insert(licences, tostring(licenceId))
						end
					end
					self.detailMeta.Text = string.format(
						"DATE OF BIRTH\n%s\n\nLICENCES\n%s\n\nDRIVING POINTS\n%d\n\nACCESS PROFILE\nRoad-safety view",
						tostring(record.DateOfBirth or "Not recorded"),
						if #licences > 0 then table.concat(licences, ", ") else "None recorded",
						record.DrivingRecord and record.DrivingRecord.Points or 0
					)
				elseif record.FullName then
					local licences = {}
					for licenceId, value in record.Licences or {} do
						if value then
							table.insert(licences, tostring(licenceId))
						end
					end
					local bookings = record.CustodyRecord and record.CustodyRecord.Bookings or {}
					local warrants = {}
					for _, warrant in record.Warrants or {} do
						table.insert(warrants, tostring(warrant.Reason or "Active warrant"))
					end
					self.detailMeta.Text = string.format(
						"DATE OF BIRTH\n%s\n\nLICENCES\n%s\n\nDRIVING POINTS · %d   CUSTODY BOOKINGS · %d\n\nFLAGS\n%s\n\nACTIVE WARRANTS\n%s",
						tostring(record.DateOfBirth or "Not recorded"),
						if #licences > 0 then table.concat(licences, ", ") else "None recorded",
						record.DrivingRecord and record.DrivingRecord.Points or 0,
						#bookings,
						if #(record.Flags or {}) > 0
							then table.concat(record.Flags, ", ")
							else "No active flags",
						if #warrants > 0 then table.concat(warrants, "\n") else "None"
					)
				elseif record.Title then
					self.detailMeta.Text = string.format(
						"STATUS\n%s\n\nTYPE\n%s\n\nLOCATION\n%s\n\nPRIORITY\n%s\n\nCREATED\n%s\n\nUNITS\n%s",
						tostring(record.Status or "Unknown"),
						tostring(record.IncidentType or "General"),
						tostring(record.Location or "Not recorded"),
						tostring(record.Priority or "Not recorded"),
						os.date("!%Y-%m-%d %H:%M UTC", record.CreatedAt or 0),
						if #(record.UnitIds or {}) > 0
							then table.concat(record.UnitIds, ", ")
							else "None recorded"
					)
				else
					self.detailMeta.Text = string.format(
						"REGISTRATION\n%s\n\nVEHICLE TYPE\n%s\n\nOWNER RECORD\n%s\n\nFLAGS\n%s",
						tostring(record.Registration or "Unknown"),
						tostring(record.DefinitionId or "Unknown"),
						tostring(record.OwnerCharacterId or "Unavailable"),
						if #(record.Flags or {}) > 0
							then table.concat(record.Flags, ", ")
							else "No active flags"
					)
				end
			end)
		end
	end

	function MDTController:_issueWarrant()
		local record = self.selectedRecord
		if not record or not self.canWriteWarrants then
			return
		end
		local days = tonumber(self.warrantExpiry.Text)
		if self.warrantExpiry.Text ~= "" and (not days or days < 1 or days > 365) then
			self.status.Text = "Expiry must be between 1 and 365 days."
			return
		end
		local response = self.context.Controllers.NetworkController:Request("MDTCreateWarrant", {
			CharacterId = record.CharacterId,
			Reason = self.warrantReason.Text,
			ExpiresAt = days and (os.time() + math.floor(days) * 86400) or nil,
		})
		self.status.Text = response.Message
		if response.Success then
			self.warrantModal.Visible = false
			self.warrantReason.Text = ""
			self.warrantExpiry.Text = ""
			self:_performSearch()
		end
	end

	function MDTController:_revokeWarrant()
		local record = self.selectedRecord
		local warrant = record and (record.Warrants or {})[1]
		if not record or not warrant or not self.canWriteWarrants then
			return
		end
		if self.revokeConfirmationId ~= warrant.WarrantId then
			self.revokeConfirmationId = warrant.WarrantId
			self.revokeAction.Text = "CONFIRM REVOKE"
			task.delay(5, function()
				if self.revokeConfirmationId == warrant.WarrantId then
					self.revokeConfirmationId = nil
					self.revokeAction.Text = "REVOKE WARRANT"
				end
			end)
			return
		end
		self.revokeConfirmationId = nil
		local response = self.context.Controllers.NetworkController:Request("MDTRevokeWarrant", {
			CharacterId = record.CharacterId,
			WarrantId = warrant.WarrantId,
		})
		self.status.Text = response.Message
		if response.Success then
			self:_performSearch()
		end
	end

	function MDTController:_performSearch()
		-- Home and the map have no record type to search. Their controls are hidden,
		-- so this is unreachable today, but sending the page name as a record type
		-- would be rejected by the server and reported to the officer as a failed
		-- search rather than as a page that simply has none.
		if
			self.recordType ~= "Person"
			and self.recordType ~= "Vehicle"
			and self.recordType ~= "Incident"
			and self.recordType ~= "Resolved"
		then
			return
		end
		self.status.Text = "Searching secure records…"
		local response = if self.recordType == "Incident" or self.recordType == "Resolved"
			then self.context.Controllers.NetworkController:Request("MDTGetIncidents", {
				Page = 1,
				ResolvedOnly = self.recordType == "Resolved",
			})
			else self:Search(self.recordType, self.input.Text, 1)
		if response.Success then
			local items = response.Data.Items or {}
			self.status.Text = string.format("%d result%s", #items, if #items == 1 then "" else "s")
			self:_renderResults(items)
		else
			self.status.Text = response.Message
		end
	end

	function MDTController:RefreshAccess()
		local response = self.context.Controllers.NetworkController:Request("GetMDTAccess", {})
		self.allowed = response.Success and response.Data.Allowed == true
		self.departmentId = if self.allowed then response.Data.DepartmentId else nil
		local service = departmentUI(self.departmentId)
		if self.serviceTitle then
			self.serviceTitle.Text = service.Title
			self.serviceSubtitle.Text = service.Subtitle
		end
		if self.classification then
			self.classification.BackgroundColor3 = if self.allowed
				then service.Accent
				else C.Classification
		end
		self:_buildHome()
		self.canWriteWarrants = self.allowed
			and table.find(response.Data.Permissions or {}, "WarrantWrite") ~= nil
		if self.allowed then
			self.secureLabel.Text = "●  "
				.. tostring(response.Data.DepartmentId or "AUTHORISED"):upper()
		end
		self.gui.Enabled = self.allowed
		-- The MDT is a persistent UX surface, not an equipment item. Emergency
		-- departments do not need an authored Tool in their loadout just to access
		-- their authorised terminal; the compact launcher remains available beside
		-- the other service controls and the M shortcut still works.
		self.launcher.Visible = self.allowed
		if not self.allowed then
			self.setOpen(false)
		end
		if self.warrantAction then
			self.warrantAction.Visible = self.selectedRecord ~= nil and self.canWriteWarrants
		end
		if self.revokeAction then
			self.revokeAction.Visible = self.selectedRecord ~= nil
				and self.canWriteWarrants
				and #((self.selectedRecord and self.selectedRecord.Warrants) or {}) > 0
		end
	end
end
