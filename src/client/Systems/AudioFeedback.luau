--!strict
--[[
	AudioFeedback.luau
	Shared UI audio feedback system for RoleplayOS.
	Wired into buttons, modals, notifications, radio, success, and error actions.
]]

local SoundService = game:GetService("SoundService")

local AudioFeedback = {}
AudioFeedback.__index = AudioFeedback

local SOUNDS = {
	ButtonClick = {
		Id = "rbxassetid://9113083740",
		Volume = 0.25,
		Speed = 1.2,
	},
	PanelOpen = {
		Id = "rbxassetid://9113083980",
		Volume = 0.15,
		Speed = 1.0,
	},
	Success = {
		Id = "rbxassetid://9113084210",
		Volume = 0.18,
		Speed = 1.0,
	},
	Error = {
		Id = "rbxassetid://9113084450",
		Volume = 0.25,
		Speed = 0.9,
	},
	Notification = {
		Id = "rbxassetid://9113084680",
		Volume = 0.16,
		Speed = 1.1,
	},
	RadioTransmit = {
		Id = "rbxassetid://9113084910",
		Volume = 0.18,
		Speed = 1.0,
	},
	PanicAlarm = {
		Id = "rbxassetid://9113085140",
		Volume = 0.32,
		Speed = 1.0,
	},
}

function AudioFeedback.new(context)
	local self = setmetatable({}, AudioFeedback)
	self.context = context
	self.enabled = true
	self.muted = false

	if context and context.Controllers and context.Controllers.SettingsController then
		local settings = context.Controllers.SettingsController
		local values = settings:Get()
		if values then
			self.enabled = values.UISounds ~= false
		end
	end

	local masterVolume = SoundService.Volume
	if masterVolume and masterVolume <= 0 then
		self.muted = true
	end

	self.soundGroup = Instance.new("SoundGroup")
	self.soundGroup.Name = "RoleplayOS_UI"
	self.soundGroup.Volume = 1
	self.soundGroup.Parent = SoundService

	self.sounds = {}
	for name, config in SOUNDS do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = config.Id
		sound.Volume = config.Volume
		sound.PlaybackSpeed = config.Speed
		sound.SoundGroup = self.soundGroup
		sound.Parent = self.soundGroup
		self.sounds[name] = sound
	end

	return self
end

function AudioFeedback:_canPlay()
	if not self.enabled then
		return false
	end
	if self.muted then
		return false
	end
	local masterVolume = SoundService.Volume
	if masterVolume and masterVolume <= 0 then
		return false
	end
	return true
end

function AudioFeedback:Play(name: string)
	if not self:_canPlay() then
		return
	end
	local sound = self.sounds[name]
	if not sound then
		warn("[AudioFeedback] Unknown sound:", name)
		return
	end
	sound:Play()
end

function AudioFeedback:ButtonClick()
	self:Play("ButtonClick")
end

function AudioFeedback:PanelOpen()
	self:Play("PanelOpen")
end

function AudioFeedback:Success()
	self:Play("Success")
end

function AudioFeedback:Error()
	self:Play("Error")
end

function AudioFeedback:Notification()
	self:Play("Notification")
end

function AudioFeedback:RadioTransmit()
	self:Play("RadioTransmit")
end

function AudioFeedback:PanicAlarm()
	self:Play("PanicAlarm")
end

function AudioFeedback:SetEnabled(enabled: boolean)
	self.enabled = enabled
end

function AudioFeedback:Destroy()
	for _, sound in self.sounds do
		sound:Destroy()
	end
	self.sounds = {}
	if self.soundGroup then
		self.soundGroup:Destroy()
	end
end

return AudioFeedback
