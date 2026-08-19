--!strict

-- Speeding: who is exempt, what it costs, and where it is recorded.
--
-- Detection is not here. The speed camera system placed in the world measures
-- the speed and calls IssueFine; this decides whether the driver should have
-- been fined at all, works out the penalty, and writes it to the character's
-- driving record so the MDT shows it and RecordIndexService publishes it into
-- the person record. A camera keeping its own tally somewhere else is invisible
-- to every one of those.
--
-- The exemption is the interesting part. An emergency driver on a blue light run
-- is not speeding, they are responding; the same driver with the lights off is
-- just speeding in a marked car. So the exemption belongs to the response rather
-- than to the person or the vehicle, and it is checked at the moment the camera
-- reports, because that is the only moment it is true of.

local ServerStorage = game:GetService("ServerStorage")

-- The name a camera system looks for. A BindableFunction rather than a module,
-- so a script that knows nothing about RoleplayOS and cannot require anything
-- from it can still ask.
local BRIDGE_NAME = "RoleplayOSIssueFine"

local RoadSafetyService = {
	sensors = {},
	taggedSensors = {},
	cooldowns = {},
	journeys = {},
	seatByAssembly = setmetatable({}, { __mode = "k" }),
	running = false,
}

local CameraDetection = require(script.CameraDetection)
local LightsExemption = require(script.LightsExemption)
local Fines = require(script.Fines)

-- Each of these attaches a group of methods onto RoadSafetyService directly
-- (they only need `self`, not a lexical upvalue) - the same split used for
-- NetworkService, DataService, VehicleSpawnerService and CustodyService this
-- session. Order does not matter: nothing here runs until a caller invokes a
-- method, well after every group is attached.
CameraDetection(RoadSafetyService)
LightsExemption(RoadSafetyService)
Fines(RoadSafetyService)

function RoadSafetyService:Init(context: any)
	self.context = context
	self.connections = {}
	self.fineEvent = context.Network:RegisterEvent("RoadSafetyFine")
end

-- A door for the camera system in the world.
--
-- It lives in ServerStorage under a fixed name, so a camera script parented
-- anywhere on the server can find it without requiring anything, and it takes
-- the same table IssueFine does. Anything that goes wrong inside is reported to
-- the caller rather than raised, since a camera should not stop working because
-- one reading was malformed.
function RoadSafetyService:Start()
	local bridge = Instance.new("BindableFunction")
	bridge.Name = BRIDGE_NAME
	bridge.OnInvoke = function(request: any)
		local ok, issued, reason = pcall(function()
			return self:IssueFine(request)
		end)
		if not ok then
			self.context.Logger:Error("Speed camera fine raised", { Error = tostring(issued) })
			return false, "ISSUE_FAILED"
		end
		return issued, reason
	end
	bridge.Parent = ServerStorage
	self.bridge = bridge
	self:_adoptCameras()
	self:_startTaggedSensors()
end

function RoadSafetyService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.taggedSensors do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.sensors)
	table.clear(self.taggedSensors)
	table.clear(self.cooldowns)
	table.clear(self.journeys)
	if self.bridge then
		self.bridge:Destroy()
		self.bridge = nil
	end
end

return RoadSafetyService
