--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DispatchPolicy = require(ReplicatedStorage.RoleplayOS.Shared.DispatchPolicy)
local MapProjection = require(ReplicatedStorage.RoleplayOS.Shared.MapProjection)
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local DispatchService = { Optional = true, connections = {}, occupied = {}, running = false }

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

function DispatchService:Init(context: any)
	self.context = context
	self.changedEvent = context.Network:RegisterEvent("DispatchChanged")
	self.accessEvent = context.Network:RegisterEvent("DispatchConsoleAccess")
	self.seatWatchers = {}
end

function DispatchService:_duty(player: Player): any?
	return self.context.Services:Get("DutyService"):Get(player)
end

function DispatchService:_dispatchSeat(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid then humanoid.SeatPart else nil
	if
		seat
		and (seat:IsA("Seat") or seat:IsA("VehicleSeat"))
		and CollectionService:HasTag(seat, self.context.Configuration.Dispatch.SeatTag)
	then
		return seat
	end
	return nil
end

function DispatchService:IsAtConsole(player: Player): boolean
	if not self.running or not playerIsCurrent(player) then
		return false
	end
	local seat = self:_dispatchSeat(player)
	if not seat then
		return false
	end
	local studioAccess = RunService:IsStudio()
		and self.context.Configuration.Framework.GrantMockEmergencyAccessInStudio == true
	if studioAccess then
		return true
	end

	-- DutyService:Get can yield while Roblox answers a group lookup. The seat
	-- captured before that call is therefore only provisional: standing up,
	-- changing character or leaving during the lookup must revoke dispatch access
	-- before this authority check returns.
	local duty = self:_duty(player)
	return self.running
		and playerIsCurrent(player)
		and self:_dispatchSeat(player) == seat
		and DispatchPolicy.canDispatch(
			duty,
			self.context.Configuration.Dispatch.DispatcherDepartments,
			true
		)
end

function DispatchService:_sendAccess(player: Player)
	local allowed = self:IsAtConsole(player)
	self.occupied[player.UserId] = if allowed then true else nil
	if playerIsCurrent(player) then
		self.accessEvent:FireClient(player, { Allowed = allowed })
	end
end

function DispatchService:_filter(player: Player, value: string): (string?, string?)
	value = string.sub(string.match(value, "^%s*(.-)%s*$") or "", 1, 300)
	if value == "" then
		return nil, "EMPTY_TEXT"
	end
	return TextFilter.forBroadcast(value, player.UserId, Enum.TextFilterContext.PublicChat)
end

function DispatchService:PrepareCall(player: Player, payload: any): (any?, string?)
	if not table.find(self.context.Configuration.Dispatch.IncidentTypes, payload.IncidentType) then
		return nil, "INVALID_INCIDENT_TYPE"
	end
	local summary, summaryReason = self:_filter(player, tostring(payload.Summary or ""))
	local location, locationReason = self:_filter(player, tostring(payload.Location or ""))
	if not summary or not location then
		return nil, summaryReason or locationReason
	end
	local callerName = "Unknown caller"
	if type(payload.CallerName) == "string" and payload.CallerName ~= "" then
		callerName = select(1, self:_filter(player, string.sub(payload.CallerName, 1, 60)))
			or callerName
	end
	local notes = ""
	if type(payload.Notes) == "string" and payload.Notes ~= "" then
		notes = select(1, self:_filter(player, string.sub(payload.Notes, 1, 300))) or ""
	end
	local departments = {}
	for _, departmentId in
		if type(payload.DepartmentIds) == "table" then payload.DepartmentIds else {}
	do
		if
			type(departmentId) == "string"
			and self.context.Configuration.Departments[departmentId]
			and not table.find(departments, departmentId)
		then
			table.insert(departments, departmentId)
		end
	end
	if #departments == 0 or (#departments == 1 and departments[1] == "Control") then
		departments = table.clone(
			self.context.Configuration.Dispatch.DefaultDepartmentsByIncidentType[payload.IncidentType]
				or { "Control" }
		)
	end
	-- Every filter above can yield. The endpoint checked the console before
	-- entering this function, but that authority is not a lease: the dispatcher
	-- must still be seated and authorised at the instant the prepared call is
	-- committed.
	if not self:IsAtConsole(player) then
		return nil, "DISPATCH_CONSOLE_REQUIRED"
	end
	return {
		Summary = string.sub(summary, 1, 160),
		Location = string.sub(location, 1, 120),
		Priority = payload.Priority,
		IncidentType = payload.IncidentType,
		CallerName = callerName,
		CallerNumber = type(payload.CallerNumber) == "string"
				and string.sub(payload.CallerNumber, 1, 20)
			or "",
		Notes = notes,
		DepartmentIds = departments,
		Source = "Dispatch",
		CreatedByUserId = player.UserId,
	},
		nil
end

function DispatchService:_unwatchSeat(instance: Instance)
	local watcher = self.seatWatchers[instance]
	if not watcher then
		return
	end
	watcher.Connection:Disconnect()
	local previous = watcher.Player
	if previous then
		self.occupied[previous.UserId] = nil
		if previous.Parent == Players then
			self.accessEvent:FireClient(previous, { Allowed = false })
		end
	end
	self.seatWatchers[instance] = nil
end

function DispatchService:_watchSeat(instance: Instance)
	if not (instance:IsA("Seat") or instance:IsA("VehicleSeat")) then
		return
	end
	self:_unwatchSeat(instance)
	local watcher: any = { Connection = nil, Player = nil }
	local function changed()
		-- Occupant changes are deferred below. A queued callback can otherwise run
		-- after the seat was untagged, replaced or the service was destroyed and
		-- repopulate state that teardown just cleared.
		if
			not self.running
			or self.seatWatchers[instance] ~= watcher
			or not instance:IsDescendantOf(workspace)
		then
			return
		end
		local previous = watcher.Player
		if previous then
			self.occupied[previous.UserId] = nil
			if playerIsCurrent(previous) then
				self.accessEvent:FireClient(previous, { Allowed = false })
			end
		end
		local occupant = instance.Occupant
		watcher.Player = if occupant then Players:GetPlayerFromCharacter(occupant.Parent) else nil
		if watcher.Player then
			self:_sendAccess(watcher.Player)
		end
	end
	watcher.Connection = instance:GetPropertyChangedSignal("Occupant"):Connect(function()
		task.defer(changed)
	end)
	self.seatWatchers[instance] = watcher
	changed()
end

function DispatchService:_fireAuthorised(payload: any, callId: string?)
	local call = callId and self.context.Services:Get("CallService").calls[callId] or nil
	for _, player in Players:GetPlayers() do
		local duty = self:_duty(player)
		local relevant = duty
			and (
				duty.DepartmentId == "Control"
				or not call
				or table.find(call.DepartmentIds, duty.DepartmentId)
			)
		if relevant and self.context.Services:Get("MDTService"):CanUse(player) then
			self.changedEvent:FireClient(player, payload)
		end
	end
	-- A Control-created call is also a live operational alert. The dispatch
	-- board is useful for supervisors, but responding units need the same prompt
	-- a civilian 999 call or radio panic produces even when their MDT is closed.
	local createdCall = callId and self.context.Services:Get("CallService").calls[callId] or nil
	if payload.Kind == "CallCreated" and createdCall and createdCall.Source == "Dispatch" then
		self.context.Services:Get("EmergencyTriggerService"):Broadcast(createdCall)
	end
end

function DispatchService:Publish(kind: string, id: string, revision: number)
	local payload = { Kind = kind, Id = id, Revision = revision, ServerId = game.JobId }
	self:_fireAuthorised(payload, id)
end

function DispatchService:Snapshot(player: Player): (any?, string?)
	local mdt = self.context.Services:Get("MDTService")
	local studioConsole = RunService:IsStudio()
		and self.context.Configuration.Framework.GrantMockEmergencyAccessInStudio == true
		and self:IsAtConsole(player)
	local duty = if studioConsole then self:_duty(player) else mdt:GetAuthorisedDuty(player, "Dispatch")
	if not studioConsole and not duty then
		return nil, "DISPATCH_NOT_AUTHORISED"
	end
	local calls = {}
	for _, call in self.context.Services:Get("CallService"):Snapshot() do
		if
			duty
			and (
				duty.DepartmentId == "Control" or table.find(call.DepartmentIds, duty.DepartmentId)
			)
		then
			table.insert(calls, call)
		end
	end
	local units = {}
	for _, unit in self.context.Services:Get("UnitService"):Snapshot() do
		if duty and (duty.DepartmentId == "Control" or unit.DepartmentId == duty.DepartmentId) then
			-- Live position is runtime only and resolved server-side; the client
			-- never supplies it. Units off-map or without a character simply
			-- carry no position and are listed without a map marker.
			local other = Players:GetPlayerByUserId(unit.UserId)
			local rootPart = other
				and other.Character
				and other.Character:FindFirstChild("HumanoidRootPart")
			if rootPart and rootPart:IsA("BasePart") then
				unit.Position = MapProjection.serialise(rootPart.Position)
			end
			table.insert(units, unit)
		end
	end
	local atConsole = self:IsAtConsole(player)
	-- DutyService:Get can yield while access is re-evaluated. The first
	-- authorisation therefore cannot be treated as a lease over the remainder of
	-- this snapshot: a player may leave, end duty or change role before the data
	-- is returned. Require the exact authorised duty record captured above to
	-- still be current after the final yielding check.
	if not studioConsole and mdt:GetAuthorisedDuty(player, "Dispatch") ~= duty then
		return nil, "DISPATCH_NOT_AUTHORISED"
	end
	return {
		Calls = calls,
		Units = units,
		AtConsole = atConsole,
	}, nil
end

function DispatchService:Start()
	self.running = true
	for _, seat in CollectionService:GetTagged(self.context.Configuration.Dispatch.SeatTag) do
		self:_watchSeat(seat)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(self.context.Configuration.Dispatch.SeatTag)
			:Connect(function(seat)
				self:_watchSeat(seat)
			end)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(self.context.Configuration.Dispatch.SeatTag)
			:Connect(function(seat)
				self:_unwatchSeat(seat)
			end)
	)
end

function DispatchService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for _, watcher in self.seatWatchers do
		watcher.Connection:Disconnect()
	end
	table.clear(self.seatWatchers)
	table.clear(self.occupied)
end

return DispatchService
