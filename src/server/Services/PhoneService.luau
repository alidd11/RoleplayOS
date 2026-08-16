--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapProjection = require(ReplicatedStorage.RoleplayOS.Shared.MapProjection)
local PhoneValidator = require(ReplicatedStorage.RoleplayOS.Shared.PhoneValidator)
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local PhoneService = { calls = {}, userCalls = {}, connections = {} }

local function isPhoneTool(instance: Instance): boolean
	return instance:IsA("Tool")
		and (instance.Name == "Phone" or instance:GetAttribute("RoleplayOSToolId") == "Phone")
end

local function findPhoneTool(player: Player, includeBackpack: boolean): Tool?
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if isPhoneTool(child) then
				return child :: Tool
			end
		end
	end

	if includeBackpack then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			for _, child in backpack:GetChildren() do
				if isPhoneTool(child) then
					return child :: Tool
				end
			end
		end
	end

	return nil
end

function PhoneService:_makeTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Phone"
	tool.ToolTip = "RoleplayOS Mobile"
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.62, 1.18, 0.12)
	handle.Color = Color3.fromRGB(16, 18, 22)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Size = Vector3.new(0.53, 0.97, 0.025)
	screen.Color = Color3.fromRGB(40, 105, 180)
	screen.Material = Enum.Material.Glass
	screen.CanCollide = false
	screen.Massless = true
	screen.CFrame = handle.CFrame * CFrame.new(0, 0, -0.071)
	screen.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = screen
	weld.Parent = screen
	local light = Instance.new("SpotLight")
	light.Name = "PhoneFlashlight"
	light.Enabled = false
	light.Brightness = 2.5
	light.Range = 28
	light.Angle = 58
	light.Face = Enum.NormalId.Back
	light.Parent = handle
	-- Translation first, then rotation, matching the other tools. Written the
	-- other way round the offset is applied in the rotated frame and pushes the
	-- handset sideways, and the quarter turn about Y left the flat body edge on
	-- to the camera so it read as being held wrong.
	tool.Grip = CFrame.new(0, -0.1, -0.6) * CFrame.Angles(math.rad(90), 0, 0)
	return tool
end

function PhoneService:EnsureTool(player: Player)
	if not self:_character(player) then
		return
	end
	if findPhoneTool(player, true) then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	self:_makeTool().Parent = backpack
end

function PhoneService:ToggleFlashlight(player: Player, enabled: any): (boolean, string?)
	if type(enabled) ~= "boolean" then
		return false, "INVALID_FLASHLIGHT_STATE"
	end
	local tool = findPhoneTool(player, false)
	local light = tool and tool:FindFirstChild("PhoneFlashlight", true)
	if not light or not light:IsA("SpotLight") then
		return false, "PHONE_MUST_BE_EQUIPPED"
	end
	light.Enabled = enabled
	return true, nil
end

function PhoneService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("PhoneChanged")
end

function PhoneService:_character(player: Player): any?
	local session = self.context.Services:Get("DataService"):GetSession(player)
	return session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
end

function PhoneService:_ensurePhone(character: any): any
	character.Phone = character.Phone
		or {
			Number = PhoneValidator.numberFromCharacterId(character.CharacterId),
			Messages = {},
		}
	return character.Phone
end

function PhoneService:_findByNumber(number: string): (Player?, any?)
	for _, player in Players:GetPlayers() do
		local character = self:_character(player)
		if character and self:_ensurePhone(character).Number == number then
			return player, character
		end
	end
	return nil, nil
end

function PhoneService:_filter(message: string, from: Player, to: Player): (string?, string?)
	return TextFilter.forUser(message, from.UserId, to.UserId, Enum.TextFilterContext.PrivateChat)
end

function PhoneService:_filterBroadcast(message: string, from: Player): (string?, string?)
	return TextFilter.forBroadcast(message, from.UserId, Enum.TextFilterContext.PublicChat)
end

function PhoneService:_append(player: Player, character: any, message: any)
	local phone = self:_ensurePhone(character)
	table.insert(phone.Messages, message)
	local maximum = self.context.Configuration.Phone.MaximumMessages
	while #phone.Messages > maximum do
		table.remove(phone.Messages, 1)
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
end

-- Server-originated phone notifications use the same persisted inbox as texts,
-- so a taxi request remains visible when the player opens the handset later.
function PhoneService:AppendSystemMessage(player: Player, character: any, message: any)
	self:_append(player, character, message)
	self.event:FireClient(player, { Kind = message.Kind or "System", Message = message })
end

function PhoneService:Snapshot(player: Player): (any?, string?)
	local character = self:_character(player)
	if not character then
		return nil, "ACTIVE_CHARACTER_REQUIRED"
	end
	local phone = self:_ensurePhone(character)
	self:EnsureTool(player)
	local contacts = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherCharacter = self:_character(other)
			if otherCharacter then
				table.insert(contacts, {
					Name = otherCharacter.Identity.FirstName
						.. " "
						.. otherCharacter.Identity.LastName,
					Number = self:_ensurePhone(otherCharacter).Number,
				})
			end
		end
	end
	local transactions = {}
	local sourceTransactions = character.Economy.Transactions or {}
	for index = #sourceTransactions, math.max(1, #sourceTransactions - 19), -1 do
		local transaction = sourceTransactions[index]
		table.insert(transactions, {
			Amount = transaction.Amount,
			Direction = transaction.Direction,
			Description = transaction.Description or transaction.ReasonCode or "Transaction",
			Timestamp = transaction.Timestamp,
		})
	end
	return {
		Number = phone.Number,
		Messages = table.clone(phone.Messages),
		Contacts = contacts,
		-- The wallet renders the holder's own credentials only. Presenting them
		-- to somebody else still goes through IdentificationService, which
		-- enforces the equipped card and proximity rules.
		Identity = {
			FirstName = character.Identity.FirstName,
			LastName = character.Identity.LastName,
			DateOfBirth = character.Identity.DateOfBirth,
			CharacterId = character.CharacterId,
		},
		Bank = {
			Balance = character.Economy.Balance,
			Cash = character.Economy.Cash,
			Transactions = transactions,
			TransferMaximum = self.context.Configuration.Economy.TransferMaximum,
		},
		EmergencyNumber = self.context.Configuration.Phone.EmergencyNumber,
		ActiveCall = self.userCalls[player.UserId] and self.calls[self.userCalls[player.UserId]]
			or nil,
		Taxi = self.context.Services:Get("TaxiService"):GetStatus(player),
		TaxiDriverRequest = self.context.Services:Get("TaxiService"):GetDriverRequest(player),
	},
		nil
end

-- Finds a player in this server by Roblox username, or by display name.
--
-- Case is ignored and surrounding spaces are trimmed, because somebody typing a
-- name they read off a nameplate should not have to match its capitals. An
-- ambiguous display name is refused rather than guessed at: two people can share
-- one, and sending money to the wrong one of them is not recoverable.
function PhoneService:_findByName(query: string): (Player?, string?)
	local wanted = string.lower(string.match(query, "^%s*(.-)%s*$") or "")
	if wanted == "" then
		return nil, "INVALID_RECIPIENT_NAME"
	end
	local byDisplay = nil
	local displayMatches = 0
	for _, other in Players:GetPlayers() do
		if string.lower(other.Name) == wanted then
			-- A username is unique on Roblox, so an exact one is the answer and
			-- nothing else needs looking at.
			return other, nil
		end
		if string.lower(other.DisplayName) == wanted then
			displayMatches += 1
			byDisplay = other
		end
	end
	if displayMatches > 1 then
		return nil, "RECIPIENT_NAME_AMBIGUOUS"
	end
	return byDisplay, if byDisplay then nil else "PHONE_RECIPIENT_UNAVAILABLE"
end

function PhoneService:TransferFunds(player: Player, rawName: any, rawAmount: any): (any?, string?)
	-- By username rather than by phone number. A number is something a player has
	-- to be told before they can be paid, and there is nowhere in the game that
	-- tells them: a name is on the nameplate above the person standing there.
	if type(rawName) ~= "string" or #rawName > 64 then
		return nil, "INVALID_RECIPIENT_NAME"
	end
	local recipient, findReason = self:_findByName(rawName)
	if not recipient then
		return nil, findReason
	end
	local transfer, reason =
		self.context.Services:Get("EconomyService"):Transfer(player, recipient, rawAmount)
	if not transfer then
		return nil, reason
	end
	local senderCharacter = self:_character(player)
	local senderName = if senderCharacter
		then senderCharacter.Identity.FirstName .. " " .. senderCharacter.Identity.LastName
		else "Another player"
	self.event:FireClient(recipient, {
		Kind = "BankTransfer",
		Amount = transfer.Amount,
		From = senderName,
	})
	return transfer, nil
end

function PhoneService:SendText(player: Player, rawNumber: any, rawMessage: any): (any?, string?)
	local number = PhoneValidator.number(rawNumber)
	local message =
		PhoneValidator.message(rawMessage, self.context.Configuration.Phone.MaximumMessageLength)
	local senderCharacter = self:_character(player)
	if not number or not message or not senderCharacter then
		return nil, "INVALID_TEXT_MESSAGE"
	end
	local recipient, recipientCharacter = self:_findByNumber(number)
	if not recipient or not recipientCharacter or recipient == player then
		return nil, "PHONE_RECIPIENT_UNAVAILABLE"
	end
	local forRecipient, filterReason = self:_filter(message, player, recipient)
	if not forRecipient then
		return nil, filterReason
	end
	local forSender = select(1, self:_filter(message, player, player)) or forRecipient
	local senderPhone = self:_ensurePhone(senderCharacter)
	local id = HttpService:GenerateGUID(false)
	local timestamp = os.time()
	local sent = {
		MessageId = id,
		FromNumber = senderPhone.Number,
		ToNumber = number,
		Body = forSender,
		Direction = "Outgoing",
		Timestamp = timestamp,
	}
	local received = table.clone(sent)
	received.Body = forRecipient
	received.Direction = "Incoming"
	self:_append(player, senderCharacter, sent)
	self:_append(recipient, recipientCharacter, received)
	self.event:FireClient(recipient, { Kind = "Text", Message = received })
	return sent, nil
end

function PhoneService:PlaceCall(player: Player, rawNumber: any): (any?, string?)
	local number = PhoneValidator.number(rawNumber)
	local callerCharacter = self:_character(player)
	if not number or not callerCharacter or self.userCalls[player.UserId] then
		return nil, "CALL_UNAVAILABLE"
	end
	local recipient, recipientCharacter = self:_findByNumber(number)
	if
		not recipient
		or not recipientCharacter
		or recipient == player
		or self.userCalls[recipient.UserId]
	then
		return nil, "PHONE_RECIPIENT_UNAVAILABLE"
	end
	local call = {
		CallId = HttpService:GenerateGUID(false),
		CallerUserId = player.UserId,
		RecipientUserId = recipient.UserId,
		CallerNumber = self:_ensurePhone(callerCharacter).Number,
		RecipientNumber = number,
		State = "Ringing",
		StartedAt = os.time(),
	}
	self.calls[call.CallId] = call
	self.userCalls[player.UserId] = call.CallId
	self.userCalls[recipient.UserId] = call.CallId
	self.event:FireClient(player, { Kind = "Call", Call = call })
	self.event:FireClient(recipient, { Kind = "Call", Call = call })
	task.delay(45, function()
		local current = self.calls[call.CallId]
		if current and current.State == "Ringing" then
			local caller = Players:GetPlayerByUserId(current.CallerUserId)
			local recipientPlayer = Players:GetPlayerByUserId(current.RecipientUserId)
			if caller then
				self:EndCall(caller, current.CallId)
			elseif recipientPlayer then
				self:EndCall(recipientPlayer, current.CallId)
			else
				self.userCalls[current.CallerUserId] = nil
				self.userCalls[current.RecipientUserId] = nil
				self.calls[current.CallId] = nil
			end
		end
	end)
	return call, nil
end

function PhoneService:AnswerCall(player: Player, callId: string): (any?, string?)
	local call = self.calls[callId]
	if not call or call.RecipientUserId ~= player.UserId or call.State ~= "Ringing" then
		return nil, "CALL_NOT_ANSWERABLE"
	end
	call.State = "Connected"
	call.ConnectedAt = os.time()
	local caller = Players:GetPlayerByUserId(call.CallerUserId)
	local recipient = Players:GetPlayerByUserId(call.RecipientUserId)
	local voiceConnected = false
	local voiceReason = "VOICE_NOT_AVAILABLE"
	if caller and recipient then
		voiceConnected, voiceReason =
			self.context.Services:Get("PhoneVoiceService"):ConnectCall(callId, caller, recipient)
	end
	call.Voice = {
		Connected = voiceConnected,
		Reason = if voiceConnected then nil else voiceReason,
	}
	for _, userId in { call.CallerUserId, call.RecipientUserId } do
		local target = Players:GetPlayerByUserId(userId)
		if target then
			self.event:FireClient(target, { Kind = "Call", Call = call })
		end
	end
	return call, nil
end

function PhoneService:EndCall(player: Player, callId: string): (boolean, string?)
	local call = self.calls[callId]
	if
		not call or (call.CallerUserId ~= player.UserId and call.RecipientUserId ~= player.UserId)
	then
		return false, "CALL_NOT_FOUND"
	end
	call.State = "Ended"
	call.EndedAt = os.time()
	self.context.Services:Get("PhoneVoiceService"):DisconnectCall(callId)
	for _, userId in { call.CallerUserId, call.RecipientUserId } do
		self.userCalls[userId] = nil
		local target = Players:GetPlayerByUserId(userId)
		if target then
			self.event:FireClient(target, { Kind = "Call", Call = call })
		end
	end
	task.delay(5, function()
		self.calls[callId] = nil
	end)
	return true, nil
end

function PhoneService:Emergency(player: Player, rawSummary: any, rawLocation: any): (any?, string?)
	local character = self:_character(player)
	local summary = PhoneValidator.message(rawSummary, 120)
	local location = PhoneValidator.message(rawLocation, 80)
	if not character or not summary or not location then
		return nil, "INVALID_EMERGENCY_CALL"
	end
	local filteredSummary, reason = self:_filterBroadcast(summary, player)
	local filteredLocation = select(1, self:_filterBroadcast(location, player))
	if not filteredSummary or not filteredLocation then
		return nil, reason
	end
	-- Plot the call where the caller actually stands. Resolved server-side so a
	-- client cannot place an incident somewhere it is not.
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return self.context.Services:Get("CallService"):Create({
		Priority = "Immediate",
		Summary = "999 · " .. filteredSummary,
		Location = filteredLocation,
		Position = if rootPart and rootPart:IsA("BasePart")
			then MapProjection.serialise(rootPart.Position)
			else nil,
		CallerNumber = self:_ensurePhone(character).Number,
		DepartmentIds = { "Police", "Ambulance", "Fire", "Control" },
		IncidentType = "Emergency",
		CallerName = character.Identity.FirstName .. " " .. character.Identity.LastName,
	})
end

function PhoneService:Start()
	local function onCharacterAdded(player: Player)
		local callId = self.userCalls[player.UserId]
		if callId then
			self:EndCall(player, callId)
		end
		task.delay(1, function()
			if player.Parent then
				self:EnsureTool(player)
			end
		end)
	end
	-- Per-player handlers are held against the player rather than pushed onto the
	-- service-wide list, which is only emptied when the server shuts down. Every
	-- join added an entry there that nothing ever removed, so a busy server spent
	-- an evening accumulating one dead closure per join and walked the lot at
	-- shutdown. Disconnecting on the way out also means a player who rejoins the
	-- same server cannot end up with two handlers running for one spawn.
	self.playerConnections = {}
	local function forget(player: Player)
		local connection = self.playerConnections[player.UserId]
		if connection then
			connection:Disconnect()
			self.playerConnections[player.UserId] = nil
		end
	end
	local function watch(player: Player)
		forget(player)
		self.playerConnections[player.UserId] = player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			forget(player)
			local callId = self.userCalls[player.UserId]
			if callId then
				self:EndCall(player, callId)
			end
		end)
	)
end

function PhoneService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for _, connection in self.playerConnections or {} do
		connection:Disconnect()
	end
	table.clear(self.playerConnections or {})
	table.clear(self.calls)
	table.clear(self.userCalls)
end

return PhoneService
