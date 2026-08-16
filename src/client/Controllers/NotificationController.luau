--!strict

local NotificationController = {}

function NotificationController:Init(context: any)
	self.context = context
	self.notificationSystem = context.Systems and context.Systems.NotificationSystem or nil
	self.ownsNotificationSystem = false
end

function NotificationController:Start() end

-- Words that make a title an outcome rather than a subject.
--
-- Show is called from about forty places, and almost all of them pass a heading
-- describing what happened: "Error", "Duty unavailable", "Outfit unavailable".
-- Every one of those rendered in the same calm blue as a success, because Show
-- always called ShowInfo, so a failure and a confirmation were indistinguishable
-- at a glance -- which is the one thing a notification exists to prevent.
--
-- Reading the title is deliberate. The alternative was editing every call site
-- to pass a level, which is forty chances to miss one and leave it silently
-- wrong. Callers that want to be explicit can pass a level and skip this
-- entirely; new code should.
local FAILURE_WORDS = {
	"error",
	"unavailable",
	"required",
	"failed",
	"denied",
	"refused",
	"cannot",
	"panic",
}

local SUCCESS_WORDS = {
	"ready",
	"saved",
	"complete",
	"granted",
}

local function inferLevel(title: string?): string
	if type(title) ~= "string" then
		return "Info"
	end
	local lowered = string.lower(title)
	for _, word in FAILURE_WORDS do
		if string.find(lowered, word, 1, true) then
			return "Danger"
		end
	end
	for _, word in SUCCESS_WORDS do
		if string.find(lowered, word, 1, true) then
			return "Success"
		end
	end
	return "Info"
end

function NotificationController:Show(
	message: string,
	title: string?,
	level: string?,
	_duration: number?
)
	if not self.notificationSystem then
		local NotificationSystem = require(script.Parent.Parent.UI.NotificationSystem)
		self.notificationSystem = NotificationSystem.new(self.context)
		self.ownsNotificationSystem = true
	end
	local resolved = if type(level) == "string" then level else inferLevel(title)
	self.notificationSystem:Show(message, title or "RoleplayOS", resolved)
end

function NotificationController:ShowError(message: string)
	if not self.notificationSystem then
		local NotificationSystem = require(script.Parent.Parent.UI.NotificationSystem)
		self.notificationSystem = NotificationSystem.new(self.context)
		self.ownsNotificationSystem = true
	end
	self.notificationSystem:ShowDanger(message, "Error")
end

function NotificationController:Destroy()
	if self.ownsNotificationSystem and self.notificationSystem then
		self.notificationSystem:Destroy()
	end
	self.notificationSystem = nil
	self.ownsNotificationSystem = false
end

return NotificationController
