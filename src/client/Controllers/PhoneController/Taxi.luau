--!strict

local Utils = require(script.Parent.Utils)

local C = Utils.C
local label = Utils.label
local button = Utils.button
local input = Utils.input

return function(PhoneController)
	function PhoneController:_renderTaxi()
		local taxi = self.phoneData and self.phoneData.Taxi
		local title =
			label(self.content, if taxi then "ACTIVE BOOKING" else "BOOK A TAXI", 13, true)
		title.Size = UDim2.new(1, 0, 0, 24)
		local hint = label(
			self.content,
			if taxi then taxi.Pickup .. "  →  " .. taxi.Dropoff else "Licensed local taxi service",
			9
		)
		hint.Position = UDim2.fromOffset(0, 28)
		hint.Size = UDim2.new(1, 0, 0, 30)
		hint.TextColor3 = C.Muted
		if taxi then
			local details = label(
				self.content,
				string.format(
					"%s  ·  £%d\n%s",
					taxi.State,
					taxi.Fare,
					taxi.DriverName or "Waiting for a driver"
				),
				11,
				true
			)
			details.Position = UDim2.fromOffset(0, 70)
			details.Size = UDim2.new(1, 0, 0, 52)
			local isDriver = taxi.IsDriver == true
			local canComplete = isDriver and taxi.State == "Accepted"
			local action = button(
				self.content,
				if canComplete
					then "COMPLETE RIDE"
					elseif taxi.State == "Completed" then "CLOSE"
					else "CANCEL BOOKING",
				if canComplete then C.Green elseif taxi.State == "Completed" then C.Card else C.Red
			)
			action.Position = UDim2.fromOffset(0, 132)
			action.Size = UDim2.new(1, 0, 0, 42)
			action.Activated:Connect(function()
				if canComplete then
					local response = self.context.Controllers.NetworkController:Request(
						"TaxiComplete",
						{ RequestId = taxi.RequestId }
					)
					self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
				elseif taxi.State ~= "Completed" then
					local response = self.context.Controllers.NetworkController:Request(
						"TaxiCancel",
						{ RequestId = taxi.RequestId }
					)
					self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
				end
				self:Refresh()
			end)
			return
		end
		local pickup = input(self.content, "Pickup point")
		pickup.Position = UDim2.fromOffset(0, 68)
		pickup.Size = UDim2.new(1, 0, 0, 42)
		local dropoff = input(self.content, "Drop-off point")
		dropoff.Position = UDim2.fromOffset(0, 118)
		dropoff.Size = UDim2.new(1, 0, 0, 42)
		local bandTitle = label(self.content, "FARE BAND", 8, true)
		bandTitle.Position = UDim2.fromOffset(0, 174)
		bandTitle.Size = UDim2.new(1, 0, 0, 16)
		bandTitle.TextColor3 = C.Muted
		local selected = "Local"
		local bands = {
			{ Id = "Local", Text = "LOCAL  ·  £8" },
			{ Id = "City", Text = "CITY  ·  £14" },
			{ Id = "Long", Text = "LONG  ·  £22" },
		}
		for index, band in bands do
			local choice = button(self.content, band.Text, if index == 1 then C.Blue else C.Card)
			choice.Position = UDim2.new((index - 1) / 3, (index - 1) * 4, 0, 196)
			choice.Size = UDim2.new(1 / 3, -8, 0, 38)
			choice.Activated:Connect(function()
				selected = band.Id
				for _, child in self.content:GetChildren() do
					if child:IsA("TextButton") and child:GetAttribute("TaxiBand") == true then
						child.BackgroundColor3 = if child == choice then C.Blue else C.Card
					end
				end
			end)
			choice:SetAttribute("TaxiBand", true)
		end
		local request = button(self.content, "REQUEST TAXI", C.Green)
		request.Position = UDim2.fromOffset(0, 248)
		request.Size = UDim2.new(1, 0, 0, 44)
		request.Activated:Connect(function()
			if pickup.Text == "" or dropoff.Text == "" then
				self.context.Controllers.NotificationController:Show(
					"Enter both pickup and drop-off points.",
					"Taxi"
				)
				return
			end
			request.Active = false
			local response = self.context.Controllers.NetworkController:Request("TaxiRequest", {
				Pickup = pickup.Text,
				Dropoff = dropoff.Text,
				Band = selected,
			})
			self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
			request.Active = true
			if response.Success then
				self:Refresh()
			end
		end)
		if self.phoneData and self.phoneData.TaxiDriverRequest then
			local driverRequest = self.phoneData.TaxiDriverRequest
			-- Two ways out of an offer, as a driver expects. Declining is local to
			-- this driver: the booking stays open and the passenger keeps waiting.
			local accept = button(self.content, "ACCEPT", C.Green)
			accept.Position = UDim2.fromOffset(0, 306)
			accept.Size = UDim2.new(0.5, -5, 0, 44)
			accept.Activated:Connect(function()
				local response = self.context.Controllers.NetworkController:Request(
					"TaxiAccept",
					{ RequestId = driverRequest.RequestId }
				)
				self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
				if response.Success then
					self:Refresh()
				end
			end)
			local decline = button(self.content, "DECLINE", C.Muted)
			decline.Position = UDim2.new(0.5, 5, 0, 306)
			decline.Size = UDim2.new(0.5, -5, 0, 44)
			decline.Activated:Connect(function()
				local response = self.context.Controllers.NetworkController:Request(
					"TaxiDecline",
					{ RequestId = driverRequest.RequestId }
				)
				self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
				if response.Success then
					self:Refresh()
				end
			end)
		end
	end
end
