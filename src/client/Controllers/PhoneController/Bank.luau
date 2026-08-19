--!strict

local Utils = require(script.Parent.Utils)

local C = Utils.C
local corner = Utils.corner
local label = Utils.label
local button = Utils.button
local input = Utils.input
local money = Utils.money

return function(PhoneController)
	function PhoneController:_renderBank()
		local bank = self.phoneData and self.phoneData.Bank
		if not bank then
			local empty = label(self.content, "Banking is temporarily unavailable.", 12)
			empty.Size = UDim2.new(1, 0, 0, 40)
			empty.TextColor3 = C.Muted
			return
		end
		local balanceCard = Instance.new("Frame")
		balanceCard.BackgroundColor3 = Color3.fromRGB(24, 65, 137)
		balanceCard.BorderSizePixel = 0
		balanceCard.Size = UDim2.new(1, 0, 0, 92)
		balanceCard.Parent = self.content
		corner(balanceCard, 16)
		local caption = label(balanceCard, "AVAILABLE BALANCE", 9, true)
		caption.Position = UDim2.fromOffset(14, 12)
		caption.Size = UDim2.new(1, -28, 0, 14)
		caption.TextColor3 = Color3.fromRGB(173, 204, 255)
		local balance = label(balanceCard, money(bank.Balance), 25, true)
		balance.Position = UDim2.fromOffset(14, 28)
		balance.Size = UDim2.new(1, -28, 0, 34)
		local cash = label(balanceCard, "Cash carried  " .. money(bank.Cash), 9)
		cash.Position = UDim2.fromOffset(14, 66)
		cash.Size = UDim2.new(1, -28, 0, 14)
		cash.TextColor3 = Color3.fromRGB(173, 204, 255)

		-- By username. A phone number is something a player has to be told before
		-- they can be paid and nothing in the game tells them one; a username is on
		-- the nameplate above the person they are standing next to.
		local recipient = input(self.content, "Recipient username")
		recipient.Position = UDim2.fromOffset(0, 104)
		recipient.Size = UDim2.new(0.61, -4, 0, 42)
		recipient.TextYAlignment = Enum.TextYAlignment.Center
		recipient.AutomaticSize = Enum.AutomaticSize.None
		local amount = input(self.content, "Amount")
		amount.Position = UDim2.new(0.61, 4, 0, 104)
		amount.Size = UDim2.new(0.39, -4, 0, 42)
		amount.TextYAlignment = Enum.TextYAlignment.Center
		amount.AutomaticSize = Enum.AutomaticSize.None
		local send = button(self.content, "SEND MONEY", C.Blue)
		send.Position = UDim2.fromOffset(0, 154)
		send.Size = UDim2.new(1, 0, 0, 40)
		send.Activated:Connect(function()
			if not send.Active then
				return
			end
			-- Parenthesised, and the stripping narrowed.
			--
			-- This was tonumber(string.gsub(...)). gsub returns the string AND the
			-- number of substitutions, and as the last argument of a call both are
			-- passed, so the count arrived as tonumber's base. Zero and one are both
			-- outside the legal two to thirty six, so every amount raised, clean or
			-- not, on the first line of the handler before anything else ran. The
			-- button did nothing, said nothing, and no transfer request has ever left
			-- this client.
			--
			-- The old pattern also deleted the decimal point rather than rejecting it,
			-- which would have turned ten pounds fifty into one thousand and fifty. It
			-- now removes only spacing, the pound sign and thousands commas, and
			-- anything left that is not a digit is refused by the check below.
			local cleaned = (string.gsub(amount.Text, "[%s£,]", ""))
			local numericAmount = if string.match(cleaned, "^%d+$") then tonumber(cleaned) else nil
			if not numericAmount or numericAmount <= 0 then
				self.context.Controllers.NotificationController:Show(
					"Enter a whole-pound amount greater than zero.",
					"Bank"
				)
				return
			end
			send.Active = false
			send.Text = "SENDING…"
			local response = self.context.Controllers.NetworkController:Request(
				"PhoneTransferFunds",
				{ Recipient = recipient.Text, Amount = numericAmount }
			)
			self.context.Controllers.NotificationController:Show(response.Message, "Bank")
			if response.Success then
				amount.Text = ""
				recipient.Text = ""
				self:Refresh()
				return
			end
			send.Active = true
			send.Text = "SEND MONEY"
		end)

		local activityTitle = label(self.content, "RECENT ACTIVITY", 9, true)
		activityTitle.Position = UDim2.fromOffset(2, 208)
		activityTitle.Size = UDim2.new(1, -4, 0, 16)
		activityTitle.TextColor3 = C.Muted
		local history = Instance.new("ScrollingFrame")
		history.BackgroundTransparency = 1
		history.BorderSizePixel = 0
		history.Position = UDim2.fromOffset(0, 230)
		history.Size = UDim2.new(1, 0, 1, -230)
		history.AutomaticCanvasSize = Enum.AutomaticSize.Y
		history.CanvasSize = UDim2.new()
		history.ScrollBarThickness = 6
		history.Parent = self.content
		local historyLayout = Instance.new("UIListLayout")
		historyLayout.Padding = UDim.new(0, 7)
		historyLayout.Parent = history
		local transactions = bank.Transactions or {}
		for _, transaction in transactions do
			local row = Instance.new("Frame")
			row.BackgroundColor3 = C.Card
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -4, 0, 48)
			row.Parent = history
			corner(row, 10)
			local description = label(row, tostring(transaction.Description), 9, true)
			description.Position = UDim2.fromOffset(10, 6)
			description.Size = UDim2.new(1, -108, 0, 30)
			description.TextYAlignment = Enum.TextYAlignment.Top
			description.TextWrapped = true
			local transactionAmount = label(
				row,
				(if transaction.Direction == "Credit" then "+" else "−")
					.. money(transaction.Amount),
				10,
				true
			)
			transactionAmount.AnchorPoint = Vector2.new(1, 0)
			transactionAmount.Position = UDim2.new(1, -10, 0, 7)
			transactionAmount.Size = UDim2.fromOffset(82, 18)
			transactionAmount.TextXAlignment = Enum.TextXAlignment.Right
			transactionAmount.TextColor3 = if transaction.Direction == "Credit"
				then C.Green
				else C.Text
			local timestamp = label(
				row,
				os.date("%d %b · %H:%M", tonumber(transaction.Timestamp) or os.time()),
				8
			)
			timestamp.Position = UDim2.fromOffset(10, 34)
			timestamp.Size = UDim2.new(1, -20, 0, 14)
			timestamp.TextColor3 = C.Muted
		end
		if #transactions == 0 then
			local empty = label(history, "No transactions yet.", 10)
			empty.Size = UDim2.new(1, 0, 0, 40)
			empty.TextColor3 = C.Muted
		end
	end
end
