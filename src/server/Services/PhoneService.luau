--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhoneValidator = require(ReplicatedStorage.RoleplayOS.Shared.PhoneValidator)
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local PhoneService = { calls = {}, userCalls = {}, connections = {} }

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
	tool.Grip = CFrame.Angles(0, math.rad(90), math.rad(-10)) * CFrame.new(0, -0.25, 0)
	return tool
end

function PhoneService:EnsureTool(player: Player)
	if not self:_character(player) then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if
		not backpack
		or backpack:FindFirstChild("Phone")
		or (player.Character and player.Character:FindFirstChild("Phone"))
	then
		return
	end
	self:_makeTool().Parent = backpack
end

function PhoneService:ToggleFlashlight(player: Player, enabled: any): (boolean, string?)
	if type(enabled) ~= "boolean" then
		return false, "INVALID_FLASHLIGHT_STATE"
	end
	local tool = player.Character and player.Character:FindFirstChild("Phone")
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
	return {
		Number = phone.Number,
		Messages = table.clone(phone.Messages),
		Contacts = contacts,
		EmergencyNumber = self.context.Configuration.Phone.EmergencyNumber,
		ActiveCall = self.userCalls[player.UserId] and self.calls[self.userCalls[player.UserId]]
			or nil,
	},
		nil
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
	return self.context.Services:Get("CallService"):Create({
		Priority = "Immediate",
		Summary = "999 · " .. filteredSummary,
		Location = filteredLocation,
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
	for _, player in Players:GetPlayers() do
		table.insert(
			self.connections,
			player.CharacterAdded:Connect(function()
				onCharacterAdded(player)
			end)
		)
	end
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			table.insert(
				self.connections,
				player.CharacterAdded:Connect(function()
					onCharacterAdded(player)
				end)
			)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
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
	table.clear(self.calls)
	table.clear(self.userCalls)
end

return PhoneService
