--!strict

local RolePermissions =
	require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.RolePermissions)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local CustodyService = {
	booking = {},
	completing = {},
	cuffed = {},
	connections = {},
	commands = {},
	activeSentences = {},
	running = false,
}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local Utils = require(script.Utils)
local root = Utils.root
local humanoid = Utils.humanoid
local Sentencing = require(script.Sentencing)
local CellPlacement = require(script.CellPlacement)
local RoadsideActions = require(script.RoadsideActions)
local ChairBooking = require(script.ChairBooking)

-- Each of these attaches a group of methods onto CustodyService directly (they
-- only need `self`, not a lexical upvalue) - the same split NetworkService,
-- DataService and VehicleSpawnerService already used this session. Order does
-- not matter: nothing here runs until a caller invokes a method, well after
-- every group is attached.
Sentencing(CustodyService)
CellPlacement(CustodyService)
RoadsideActions(CustodyService)
ChairBooking(CustodyService)

function CustodyService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("CustodyChanged")
	self.chairEvent = context.Network:RegisterEvent("CustodyChairProcessed")
	self.booking = {}
	self.completing = {}
	self.cuffed = {}
	self.connections = {}
	self.commands = {}
	self.activeSentences = {}
	self.chairPrompts = {}
	self.chairPromptConnections = {}
	self.playerConnections = {}
	self.running = false
end

-- Custody is a power the role holds, not a department it belongs to.
--
-- This was `duty.DepartmentId == "Police"`, and PCSO is a Police role that is
-- free on the public tier, so search, escort, caution and booking somebody into
-- a half hour sentence were available to every player in the game.
function CustodyService:_authorised(player: Player): boolean
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil and RolePermissions.has(self.context.Configuration, duty, "Custody")
end

function CustodyService:IsAuthorisedForSeizure(player: Player): boolean
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil
		and RolePermissions.has(self.context.Configuration, duty, "Custody")
		and duty.DepartmentId == "Police"
end

function CustodyService:_lineOfSight(actor: Player, target: Player): boolean
	local actorRoot = root(actor)
	local targetRoot = root(target)
	if not actorRoot or not targetRoot then
		return false
	end
	local direction = targetRoot.Position - actorRoot.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { actor.Character, target.Character }
	return workspace:Raycast(actorRoot.Position, direction, params) == nil
end

function CustodyService:_near(actor: Player, target: Player, maximum: number): boolean
	local actorRoot = root(actor)
	local targetRoot = root(target)
	return actorRoot ~= nil
		and targetRoot ~= nil
		and (actorRoot.Position - targetRoot.Position).Magnitude <= maximum
		and self:_lineOfSight(actor, target)
end

function CustodyService:_filter(actor: Player, raw: any, maximum: number): (string?, string?)
	if type(raw) ~= "string" then
		return nil, "INVALID_GROUNDS"
	end
	local value = string.sub(string.gsub(raw, "[%c]", ""), 1, maximum)
	value = string.match(value, "^%s*(.-)%s*$") or ""
	if #value < 5 then
		return nil, "GROUNDS_REQUIRED"
	end
	local filtered, reason = TextFilter.forBroadcast(value, actor.UserId)
	if not filtered or #filtered < 5 then
		return nil, reason or "TEXT_FILTER_UNAVAILABLE"
	end
	return filtered, nil
end

function CustodyService:_nearestManaged(actor: Player): Player?
	local actorRoot = root(actor)
	if not actorRoot then
		return nil
	end
	local nearest
	local distance = self.context.Configuration.Custody.MaximumInteractionDistance
	for userId, state in self.cuffed do
		if state.OfficerUserId == actor.UserId or state.EscortedByUserId == actor.UserId then
			local target = Players:GetPlayerByUserId(userId)
			local targetRoot = target and root(target)
			if target and targetRoot then
				local current = (targetRoot.Position - actorRoot.Position).Magnitude
				if current <= distance then
					nearest = target
					distance = current
				end
			end
		end
	end
	return nearest
end

function CustodyService:_command(
	alias: string,
	secondary: string?,
	callback: (Player, string) -> ()
)
	local command = Instance.new("TextChatCommand")
	command.Name = "RoleplayOS" .. string.gsub(alias, "^/", "")
	command.PrimaryAlias = alias
	command.SecondaryAlias = secondary or ""
	command.AutocompleteVisible = true
	command.Parent = TextChatService
	table.insert(self.commands, command)
	table.insert(
		self.connections,
		command.Triggered:Connect(function(source, message)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				callback(player, message)
			end
		end)
	)
end

-- Keeps the one-second sentence timer proportional to the number of actual
-- prisoners, not the total server population. The table stores the exact Player
-- instance so a quick rejoin using the same UserId cannot inherit an old timer.
function CustodyService:_trackSentence(player: Player)
	self.activeSentences[player.UserId] = player
end

function CustodyService:_untrackSentence(player: Player)
	if self.activeSentences[player.UserId] == player then
		self.activeSentences[player.UserId] = nil
	end
end

function CustodyService:_tickSentences(now: number)
	if next(self.activeSentences) == nil then
		return
	end
	-- Snapshot ids because completing a sentence can yield through role/spawn work
	-- and can remove its own entry while this pass is still iterating.
	local userIds = {}
	for userId in self.activeSentences do
		table.insert(userIds, userId)
	end

	for _, userId in userIds do
		local player = self.activeSentences[userId]
		if not player or not playerIsCurrent(player) then
			self.activeSentences[userId] = nil
			continue
		end

		-- Guarded per prisoner. A failure for one detainee must never stop every
		-- other sentence timer in the server.
		local processed, problem = pcall(function()
			if self.activeSentences[userId] ~= player then
				return
			end
			local sentence = self:_sentence(player)
			if not sentence then
				self:_untrackSentence(player)
				return
			end
			local remaining = math.max(0, tonumber(sentence.RemainingSeconds) or 0)
			if remaining <= 0 then
				self:_untrackSentence(player)
				return
			end

			remaining = math.max(0, remaining - 1)
			sentence.RemainingSeconds = remaining
			sentence.ReleaseAt = 0
			sentence.UpdatedAt = now
			player:SetAttribute("RoleplayOSCustodyReleaseAt", now + remaining)
			player:SetAttribute("RoleplayOSCustodyRemaining", remaining)
			if remaining == 0 then
				local completed, completeReason = self:_completeSentence(player, "Served", nil)
				if
					not self.running
					or not playerIsCurrent(player)
					or self.activeSentences[userId] ~= player
					or self:_sentence(player) ~= sentence
				then
					return
				end
				if not completed then
					-- Retried rather than left at a permanently zeroed timer. Completion
					-- can fail for transient spawn/role reasons.
					local retrySeconds = 5
					sentence.RemainingSeconds = retrySeconds
					sentence.ReleaseAt = 0
					sentence.UpdatedAt = now
					player:SetAttribute("RoleplayOSCustodyReleaseAt", now + retrySeconds)
					player:SetAttribute("RoleplayOSCustodyRemaining", retrySeconds)
					self.context.Logger:Warning("Custody release on time served failed, retrying", {
						UserId = player.UserId,
						Reason = completeReason,
					})
				end
			elseif remaining % 10 == 0 then
				self.context.Services:Get("DataService"):MarkDirty(player)
			end
		end)
		if not processed then
			self.context.Logger:Error("Custody sentence tick failed", {
				UserId = player.UserId,
				Error = tostring(problem),
			})
		end
	end
end

function CustodyService:Start()
	self.running = true
	local chairTag = self.context.Configuration.Custody.ChairTag
	for _, model in CollectionService:GetTagged(chairTag) do
		self:_watchChair(model)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(chairTag):Connect(function(model)
			self:_watchChair(model)
		end)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(chairTag):Connect(function(model)
			self:_unwatchChair(model)
		end)
	)
	local function restoreSentence(player: Player)
		task.spawn(function()
			local deadline = os.clock() + 20
			while
				self.running
				and playerIsCurrent(player)
				and not self.context.Services:Get("DataService"):GetSession(player)
				and os.clock() < deadline
			do
				task.wait(0.1)
			end
			if not self.running or not playerIsCurrent(player) then
				return
			end
			if self:HasActiveSentence(player) then
				self:_trackSentence(player)
				local summary = self:GetSentence(player)
				player:SetAttribute("RoleplayOSCustodyReleaseAt", summary.ReleaseAt)
				player:SetAttribute("RoleplayOSCustodyRemaining", summary.RemainingSeconds)
				self:SpawnInCell(player)
			end
		end)
	end
	local function watch(player: Player)
		if not self.running or not playerIsCurrent(player) then
			return
		end
		local previous = self.playerConnections[player.UserId]
		if previous then
			previous:Disconnect()
		end
		self.playerConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
			task.defer(function()
				if
					not self.running
					or not playerIsCurrent(player)
					or player.Character ~= character
				then
					return
				end
				if self:HasActiveSentence(player) then
					self:_placeInCell(player)
					return
				end
				local state = self.cuffed[player.UserId]
				if state then
					player:SetAttribute("RoleplayOSCuffed", true)
					player:SetAttribute("RoleplayOSCuffPosition", state.CuffPosition)
					local targetHumanoid = humanoid(player)
					if targetHumanoid then
						targetHumanoid.WalkSpeed =
							self.context.Configuration.Custody.CuffedWalkSpeed
						targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
					end
				end
			end)
		end)
		restoreSentence(player)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			-- Only an already processed sentence is penalised. Merely being cuffed
			-- is not an arrest and must never create a sentence by itself.
			self:AddDisconnectPenalty(player)
			self:_untrackSentence(player)
			self.cuffed[player.UserId] = nil
			local playerConnection = self.playerConnections[player.UserId]
			if playerConnection then
				playerConnection:Disconnect()
				self.playerConnections[player.UserId] = nil
			end
			local releaseUserIds = {}
			for userId, state in self.cuffed do
				if
					state.OfficerUserId == player.UserId
					or state.EscortedByUserId == player.UserId
				then
					table.insert(releaseUserIds, userId)
				end
			end
			for _, userId in releaseUserIds do
				local target = Players:GetPlayerByUserId(userId)
				if target then
					self:_release(target)
				end
			end
		end)
	)
	task.spawn(function()
		while self.running do
			task.wait(1)
			if not self.running then
				break
			end
			self:_tickSentences(os.time())
		end
	end)
	self:_command("/caution", nil, function(actor)
		local target = self:_nearestManaged(actor)
		if target then
			self:Action(actor, target.UserId, "Caution", {})
		end
	end)
	self:_command("/search", "/gowisely", function(actor, message)
		local target = self:_nearestManaged(actor)
		local grounds = string.match(message, "^%S+%s+(.+)$")
		if target and grounds then
			self:Action(actor, target.UserId, "Search", {
				Grounds = grounds,
				Power = self.context.Configuration.Custody.SearchPowers[1],
			})
		end
	end)
end

function CustodyService:Destroy()
	self.running = false
	local cuffedUserIds = {}
	for userId in self.cuffed do
		table.insert(cuffedUserIds, userId)
	end
	for _, userId in cuffedUserIds do
		local target = Players:GetPlayerByUserId(userId)
		if target then
			self:_release(target)
		end
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.playerConnections do
		connection:Disconnect()
	end
	for _, command in self.commands do
		command:Destroy()
	end
	table.clear(self.connections)
	table.clear(self.playerConnections)
	table.clear(self.commands)
	table.clear(self.booking)
	table.clear(self.completing)
	table.clear(self.cuffed)
	table.clear(self.activeSentences)
	local chairModels = {}
	for model in self.chairPrompts do
		table.insert(chairModels, model)
	end
	for _, model in chairModels do
		self:_unwatchChair(model)
	end
	table.clear(self.chairPrompts)
	table.clear(self.chairPromptConnections)
end

return CustodyService
