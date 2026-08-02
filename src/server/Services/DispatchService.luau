--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DispatchPolicy = require(ReplicatedStorage.RoleplayOS.Shared.DispatchPolicy)

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
	return seat ~= nil
		and CollectionService:HasTag(seat, self.context.Configuration.Dispatch.SeatTag)
		and DispatchPolicy.canDispatch(
			self:_duty(player),
			self.context.Configuration.Dispatch.DispatcherDepartments,
			true
		)
end

function DispatchService:_sendAccess(player: Player)
	local allowed = self:IsAtConsole(player)
	self.occupied[player.UserId] = if allowed then true else nil
	self.accessEvent:FireClient(player, { Allowed = allowed })
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

function DispatchService:_fireAuthorised(payload: any)
	for _, player in Players:GetPlayers() do
		if self.context.Services:Get("MDTService"):CanUse(player) then
			self.changedEvent:FireClient(player, payload)
		end
	end
end

function DispatchService:Publish(kind: string, id: string, revision: number)
	local payload = { Kind = kind, Id = id, Revision = revision, ServerId = game.JobId }
	self:_fireAuthorised(payload)
end

function DispatchService:Snapshot(player: Player): (any?, string?)
	if not self.context.Services:Get("MDTService"):CanUsePermission(player, "Dispatch") then
		return nil, "DISPATCH_NOT_AUTHORISED"
	end
	return {
		Calls = self.context.Services:Get("CallService"):Snapshot(),
		Units = self.context.Services:Get("UnitService"):Snapshot(),
		AtConsole = self:IsAtConsole(player),
	},
		nil
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
