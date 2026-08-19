--!strict

local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)

local C = Utils.C
local label = Utils.label
local button = Utils.button

return function(PhoneController)
	function PhoneController:_renderCall()
		self:_clear()
		self.heading.Text = "Call"
		local call = self.activeCall
		if not call then
			return
		end
		local localUserId = Players.LocalPlayer.UserId
		local other = if call.CallerUserId == localUserId
			then call.RecipientNumber
			else call.CallerNumber
		local number = label(self.content, other, 22, true)
		number.Position = UDim2.fromOffset(0, 60)
		number.Size = UDim2.new(1, 0, 0, 34)
		number.TextXAlignment = Enum.TextXAlignment.Center
		local state = label(self.content, call.State, 12)
		state.Position = UDim2.fromOffset(0, 100)
		state.Size = UDim2.new(1, 0, 0, 24)
		state.TextColor3 = C.Muted
		state.TextXAlignment = Enum.TextXAlignment.Center
		if call.State == "Ringing" and call.RecipientUserId == localUserId then
			local answer = button(self.content, "ANSWER", C.Green)
			answer.Position = UDim2.fromOffset(0, 155)
			answer.Size = UDim2.new(1, 0, 0, 46)
			answer.Activated:Connect(function()
				self.context.Controllers.NetworkController:Request(
					"PhoneAnswerCall",
					{ CallId = call.CallId }
				)
			end)
		end
		local finish = button(self.content, "END CALL", C.Red)
		finish.Position = UDim2.fromOffset(0, 216)
		finish.Size = UDim2.new(1, 0, 0, 46)
		finish.Activated:Connect(function()
			self.context.Controllers.NetworkController:Request(
				"PhoneEndCall",
				{ CallId = call.CallId }
			)
		end)
	end

	-- Mirrors the lock-screen clock. Uses the player's local time, since the
	-- handset belongs to the character rather than to the server.
end
