--!strict

local Players = game:GetService("Players")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local RadioService = { channels = {}, current = {}, messages = {} }

local CHANNELS = {
	{ Id = "Operations", Name = "Operations", DepartmentId = nil },
	{ Id = "Police", Name = "Police", DepartmentId = "Police" },
	{ Id = "Ambulance", Name = "Ambulance", DepartmentId = "Ambulance" },
	{ Id = "Fire", Name = "Fire & Rescue", DepartmentId = "Fire" },
	{ Id = "Control", Name = "Control", DepartmentId = "Control" },
}

local function findChannel(id: string): any?
	for _, channel in CHANNELS do
		if channel.Id == id then
			return channel
		end
	end
	return nil
end

function RadioService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("RadioChanged")
	self.current = {}
	self.messages = {}
	self.connections = {}
end

function RadioService:_duty(player: Player): any?
	return self.context.Services:Get("DutyService"):Get(player)
end

function RadioService:_allowed(duty: any, channel: any): boolean
	return channel.DepartmentId == nil or channel.DepartmentId == duty.DepartmentId
end

function RadioService:Snapshot(player: Player): (any?, string?)
	local duty = self:_duty(player)
	if not duty then
		return nil, "NOT_ON_DUTY"
	end
	local available = {}
	for _, channel in CHANNELS do
		if self:_allowed(duty, channel) then
			table.insert(available, channel)
		end
	end
	local selected = self.current[player.UserId]
	if
		not selected
		or not findChannel(selected)
		or not self:_allowed(duty, findChannel(selected))
	then
		selected = if duty.DepartmentId == "Police" then "Police" else "Operations"
		self.current[player.UserId] = selected
	end
	return {
		CurrentChannelId = selected,
		Channels = available,
		Messages = self.messages[selected] or {},
		Callsign = duty.Callsign
			or duty.ShoulderNumber
			or string.format("UNIT-%d", player.UserId % 1000),
		DepartmentId = duty.DepartmentId,
	},
		nil
end

function RadioService:SetChannel(player: Player, channelId: string): (any?, string?)
	local duty = self:_duty(player)
	local channel = findChannel(channelId)
	if not duty then
		return nil, "NOT_ON_DUTY"
	end
	if not channel or not self:_allowed(duty, channel) then
		return nil, "RADIO_CHANNEL_FORBIDDEN"
	end
	self.current[player.UserId] = channelId
	local snapshot = self:Snapshot(player)
	self.event:FireClient(player, { Kind = "Snapshot", Data = snapshot })
	return snapshot, nil
end

function RadioService:Transmit(player: Player, message: string): (boolean, string?)
	local duty = self:_duty(player)
	if not duty then
		return false, "NOT_ON_DUTY"
	end
	local channelId = self.current[player.UserId] or "Operations"
	local channel = findChannel(channelId)
	if not channel or not self:_allowed(duty, channel) then
		return false, "RADIO_CHANNEL_FORBIDDEN"
	end
	local cleaned = string.gsub(string.sub(message, 1, 180), "[%c]", " ")
	local filtered, filterReason =
		TextFilter.forBroadcast(cleaned, player.UserId, Enum.TextFilterContext.PublicChat)
	if not filtered then
		return false, filterReason or "TEXT_FILTER_UNAVAILABLE"
	end
	local entry = {
		ChannelId = channelId,
		Callsign = duty.Callsign
			or duty.ShoulderNumber
			or string.format("UNIT-%d", player.UserId % 1000),
		Message = filtered,
		SentAt = os.time(),
	}
	self.messages[channelId] = self.messages[channelId] or {}
	table.insert(self.messages[channelId], entry)
	while #self.messages[channelId] > 30 do
		table.remove(self.messages[channelId], 1)
	end
	for _, recipient in Players:GetPlayers() do
		local recipientDuty = self:_duty(recipient)
		if
			recipientDuty
			and self:_allowed(recipientDuty, channel)
			and self.current[recipient.UserId] == channelId
		then
			self.event:FireClient(recipient, { Kind = "Message", Data = entry })
		end
	end
	return true, nil
end

function RadioService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.current[player.UserId] = nil
		end)
	)
end

function RadioService:Destroy()
	for _, connection in self.connections or {} do
		connection:Disconnect()
	end
	table.clear(self.connections or {})
	table.clear(self.current)
	table.clear(self.messages)
end

return RadioService
