--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DispatchPolicy = require(ReplicatedStorage.RoleplayOS.Shared.DispatchPolicy)
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local DispatchService = { Optional = true, connections = {}, occupied = {} }

function DispatchService:Init(context: any)
	self.context = context
	self.changedEvent = context.Network:RegisterEvent("DispatchChanged")
	self.accessEvent = context.Network:RegisterEvent("DispatchConsoleAccess")
end

function DispatchService:_duty(player: Player): any?
	return self.context.Services:Get("DutyService"):Get(player)
end

function DispatchService:IsAtConsole(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid then humanoid.SeatPart else nil
	local studioAccess = RunService:IsStudio()
		and self.context.Configuration.Framework.GrantMockEmergencyAccessInStudio == true
	return seat ~= nil
		and CollectionService:HasTag(seat, self.context.Configuration.Dispatch.SeatTag)
		and (
			studioAccess
			or DispatchPolicy.canDispatch(
				self:_duty(player),
				self.context.Configuration.Dispatch.DispatcherDepartments,
				true
			)
		)
end

function DispatchService:_sendAccess(player: Player)
	local allowed = self:IsAtConsole(player)
	self.occupied[player.UserId] = if allowed then true else nil
	self.accessEvent:FireClient(player, { Allowed = allowed })
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

function DispatchService:_watchSeat(instance: Instance)
	if not (instance:IsA("Seat") or instance:IsA("VehicleSeat")) then
		return
	end
	local previous: Player? = nil
	local function changed()
		if previous then
			self.occupied[previous.UserId] = nil
			self.accessEvent:FireClient(previous, { Allowed = false })
		end
		local occupant = instance.Occupant
		previous = if occupant then Players:GetPlayerFromCharacter(occupant.Parent) else nil
		if previous then
			self:_sendAccess(previous)
		end
	end
	table.insert(
		self.connections,
		instance:GetPropertyChangedSignal("Occupant"):Connect(function()
			task.defer(changed)
		end)
	)
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
end

function DispatchService:Publish(kind: string, id: string, revision: number)
	local payload = { Kind = kind, Id = id, Revision = revision, ServerId = game.JobId }
	self:_fireAuthorised(payload, id)
end

function DispatchService:Snapshot(player: Player): (any?, string?)
	local studioConsole = RunService:IsStudio()
		and self.context.Configuration.Framework.GrantMockEmergencyAccessInStudio == true
		and self:IsAtConsole(player)
	if
		not studioConsole
		and not self.context.Services:Get("MDTService"):CanUsePermission(player, "Dispatch")
	then
		return nil, "DISPATCH_NOT_AUTHORISED"
	end
	local duty = self:_duty(player)
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
			table.insert(units, unit)
		end
	end
	return {
		Calls = calls,
		Units = units,
		AtConsole = self:IsAtConsole(player),
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
end

function DispatchService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.occupied)
end

return DispatchService
