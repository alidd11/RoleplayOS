--!strict
--[[
	AudioFeedback.luau
	Shared UI audio feedback system for RoleplayOS.
	Wired into buttons, modals, notifications, radio, success, and error actions.
]]

local SoundService = game:GetService("SoundService")

local AudioFeedback = {}
AudioFeedback.__index = AudioFeedback

-- Roblox's own sounds, which ship inside the client.
--
-- The seven ids here before were not audio. They were five Scripts, a
-- SolidModel and somebody's Place, belonging to seven unrelated creators, and
-- their numbers climbed in steps of about 230 - they had been arrived at by
-- counting rather than by finding real sounds. Every one failed to load, so the
-- interface has been silent the whole time while throwing seven asset errors on
-- each join.
--
-- rbxasset:// paths cannot fail the way an upload can: no permissions to grant,
-- no owner to fall out with, no network fetch. That matters more here than an
-- exact sound, because these fire on almost every interaction in the game.
local SOUNDS = {
	ButtonClick = {
		Id = "rbxasset://sounds/button.wav",
		Volume = 0.25,
		Speed = 1.2,
	},
	PanelOpen = {
		Id = "rbxasset://sounds/switch.wav",
		Volume = 0.15,
		Speed = 1.0,
	},
	Success = {
		Id = "rbxasset://sounds/electronicpingshort.wav",
		Volume = 0.18,
		Speed = 1.0,
	},
	Error = {
		Id = "rbxasset://sounds/bass.wav",
		Volume = 0.25,
		Speed = 0.9,
	},
	Notification = {
		-- pop_mid_up.wav is not in the shipped set despite appearing in lists of
		-- it. It preloaded once and failed every time after, including in place.
		Id = "rbxasset://sounds/switch3.wav",
		Volume = 0.16,
		Speed = 1.1,
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
