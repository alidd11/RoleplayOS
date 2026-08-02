--!strict

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local PhoneVoiceService = { Optional = true, routes = {}, connections = {} }

function PhoneVoiceService:Init(context: any)
	self.context = context
	self.container = Instance.new("Folder")
	self.container.Name = "RoleplayOSPhoneVoice"
	self.container.Parent = SoundService
end

local function inputFor(player: Player): AudioDeviceInput?
	local input = player:FindFirstChildWhichIsA("AudioDeviceInput")
	return if input and input:IsA("AudioDeviceInput") then input else nil
end

local function directedRoute(
	parent: Instance,
	input: AudioDeviceInput,
	recipient: Player,
	name: string
)
	-- A modest telephone-band curve keeps calls intelligible and makes the
	-- non-spatial route distinct from nearby proximity voice.
	local equalizer = Instance.new("AudioEqualizer")
	equalizer.Name = name .. "Equalizer"
	equalizer.MidRange = NumberRange.new(300, 3400)
	equalizer.LowGain = -12
	equalizer.MidGain = 0
	equalizer.HighGain = -12
	equalizer.Parent = parent
	local output = Instance.new("AudioDeviceOutput")
	output.Name = name .. "Output"
	output.Player = recipient
	output.Parent = parent
	local inputWire = Instance.new("Wire")
	inputWire.Name = name .. "InputWire"
	inputWire.SourceInstance = input
	inputWire.TargetInstance = equalizer
	inputWire.Parent = parent
	local outputWire = Instance.new("Wire")
	outputWire.Name = name .. "OutputWire"
	outputWire.SourceInstance = equalizer
	outputWire.TargetInstance = output
	outputWire.Parent = parent
end

function PhoneVoiceService:ConnectCall(
	callId: string,
	caller: Player,
	recipient: Player
): (boolean, string?)
	self:DisconnectCall(callId)
	local callerInput = inputFor(caller)
	local recipientInput = inputFor(recipient)
	if not callerInput or not recipientInput then
		return false, "VOICE_NOT_AVAILABLE"
	end
	local route = Instance.new("Folder")
	local ok, problem = pcall(function()
		route.Name = callId
		route:SetAttribute("CallerUserId", caller.UserId)
		route:SetAttribute("RecipientUserId", recipient.UserId)
		route.Parent = self.container
		directedRoute(route, callerInput, recipient, "CallerToRecipient")
		directedRoute(route, recipientInput, caller, "RecipientToCaller")
	end)
	if not ok then
		route:Destroy()
		self.context.Logger:Warning("Phone voice route unavailable", {
			CallId = callId,
			Error = tostring(problem),
		})
		return false, "VOICE_ROUTE_UNAVAILABLE"
	end
	self.routes[callId] = route
	return true, nil
end

function PhoneVoiceService:DisconnectCall(callId: string)
	local route = self.routes[callId]
	self.routes[callId] = nil
	if route then
		route:Destroy()
	end
end

function PhoneVoiceService:_disconnectPlayer(player: Player)
	local affected = {}
	for callId, route in self.routes do
		if
			route:GetAttribute("CallerUserId") == player.UserId
			or route:GetAttribute("RecipientUserId") == player.UserId
		then
			table.insert(affected, callId)
		end
	end
	for _, callId in affected do
		self:DisconnectCall(callId)
	end
end

function PhoneVoiceService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self:_disconnectPlayer(player)
		end)
	)
end

function PhoneVoiceService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	local callIds = {}
	for callId in self.routes do
		table.insert(callIds, callId)
	end
	for _, callId in callIds do
		self:DisconnectCall(callId)
	end
	if self.container then
		self.container:Destroy()
	end
end

return PhoneVoiceService
