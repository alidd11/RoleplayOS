--!strict

local Lighting = game:GetService("Lighting")
local UKTimeService = { running = false }
function UKTimeService:Init(context: any)
	self.context = context
end

local function lastSunday(year: number, month: number): number
	local nextMonth = if month == 12
		then os.time({ year = year + 1, month = 1, day = 1, hour = 0 })
		else os.time({ year = year, month = month + 1, day = 1, hour = 0 })
	local last = os.date("!*t", nextMonth - 86400)
	return last.day - ((last.wday - 1) % 7)
end

local function isBST(timestamp: number): boolean
	local t = os.date("!*t", timestamp)
	if t.month < 3 or t.month > 10 then
		return false
	end
	if t.month > 3 and t.month < 10 then
		return true
	end
	local boundary = lastSunday(t.year, t.month)
	return if t.month == 3
		then t.day > boundary or (t.day == boundary and t.hour >= 1)
		else t.day < boundary or (t.day == boundary and t.hour < 1)
end

function UKTimeService:_apply()
	local now = os.time()
	local utc = os.date("!*t", now)
	local hour = (utc.hour + if isBST(now) then 1 else 0) % 24
	Lighting.ClockTime = hour + utc.min / 60 + utc.sec / 3600
	Lighting.GeographicLatitude = 50.8
	Lighting:SetAttribute("RoleplayOSUKTimeZone", if isBST(now) then "BST" else "GMT")
end

function UKTimeService:Start()
	if not self.context.Configuration.UKTime.Enabled then
		return
	end
	self.running = true
	self:_apply()
	task.spawn(function()
		while self.running do
			task.wait(self.context.Configuration.UKTime.UpdateSeconds)
			self:_apply()
		end
	end)
end
function UKTimeService:Destroy()
	self.running = false
end
return UKTimeService
