--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LevelProgression = require(ReplicatedStorage.RoleplayOS.Shared.LevelProgression)
local ProgressionVisibility = require(ReplicatedStorage.RoleplayOS.Shared.ProgressionVisibility)

local ProgressionService = {}

function ProgressionService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("ProgressionChanged")
end

function ProgressionService:Start() end

function ProgressionService:_state(character: any): any
	local state = character.Progression
	if type(state) ~= "table" or type(state.TotalXP) ~= "number" then
		state = { TotalXP = 0, Tracks = {}, RewardIds = {}, RewardOrder = {}, History = {} }
		character.Progression = state
	end
	state.Tracks = state.Tracks or {}
	state.RewardIds = state.RewardIds or {}
	state.RewardOrder = state.RewardOrder or {}
	state.History = state.History or {}
	return state
end

function ProgressionService:_summary(state: any): any
	local config = self.context.Configuration.Progression
	local summary = LevelProgression.fromXp(
		state.TotalXP,
		config.BaseXP,
		config.GrowthFactor,
		config.MaximumLevel
	)
	summary.Tracks = {}
	for trackId, trackXp in state.Tracks do
		summary.Tracks[trackId] = LevelProgression.fromXp(
			trackXp,
			config.BaseXP,
			config.GrowthFactor,
			config.MaximumLevel
		)
	end
	return summary
end

function ProgressionService:Get(player: Player, characterId: string?): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local selectedId = characterId or (session and session.ActiveCharacterId)
	local character = selectedId and session and session.Profile.Characters[selectedId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	return self:_summary(self:_state(character)), nil
end

function ProgressionService:GetPublicHud(player: Player): (any?, string?)
	local team = player.Team
	local teamDefinition = team and self.context.Configuration.Teams[team.Name]
	local serverKind = if game.PrivateServerId == "" then "Public" else "Private"
	if not ProgressionVisibility.isPublicHudAllowed(serverKind, teamDefinition) then
		return nil, "PUBLIC_PROGRESSION_UNAVAILABLE"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
	if not character then
		return nil, "CHARACTER_NOT_ACTIVE"
	end
	local state = self:_state(character)
	local overall = self:_summary(state)
	local roles = {}
	for _, role in self.context.Configuration.Roles do
		if role.TeamName == team.Name and role.Access.AccessType == "Public" then
			local trackId = "Role:" .. role.Id
			local track = state.Tracks[trackId] and overall.Tracks[trackId] or overall
			table.insert(roles, {
				Id = role.Id,
				Name = role.Name,
				Kind = "Role",
				TrackId = trackId,
				Progression = track,
			})
		end
	end
	for _, job in self.context.Configuration.Jobs do
		if job.Class == "Public" then
			local trackId = "Job:" .. job.Id
			local track = state.Tracks[trackId] and overall.Tracks[trackId]
				or self:_summary({ TotalXP = 0, Tracks = {} })
			table.insert(roles, {
				Id = job.Id,
				Name = job.Name,
				Kind = "Job",
				TrackId = trackId,
				Progression = track,
			})
		end
	end
	table.sort(roles, function(a, b)
		return a.Name < b.Name
	end)
	return {
		Visible = true,
		Team = { Id = teamDefinition.Id, Name = teamDefinition.Name },
		Overall = overall,
		Roles = roles,
	},
		nil
end

function ProgressionService:Grant(
	player: Player,
	characterId: string,
	rewardId: string,
	trackId: string,
	amount: number,
	reasonCode: string
): (any?, string?)
	local config = self.context.Configuration.Progression
	if
		type(rewardId) ~= "string"
		or #rewardId < 1
		or #rewardId > 96
		or type(trackId) ~= "string"
		or #trackId < 1
		or #trackId > 48
		or type(amount) ~= "number"
		or amount % 1 ~= 0
		or amount <= 0
		or amount > config.MaximumGrant
	then
		return nil, "INVALID_XP_GRANT"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	local state = self:_state(character)
	if state.RewardIds[rewardId] then
		return nil, "DUPLICATE_XP_REWARD"
	end
	local before = self:_summary(state)
	state.TotalXP += amount
	state.Tracks[trackId] = (state.Tracks[trackId] or 0) + amount
	state.RewardIds[rewardId] = os.time()
	table.insert(state.RewardOrder, rewardId)
	while #state.RewardOrder > config.MaximumRewardIds do
		local expiredRewardId = table.remove(state.RewardOrder, 1)
		state.RewardIds[expiredRewardId] = nil
	end
	table.insert(state.History, 1, {
		RewardId = rewardId,
		TrackId = trackId,
		Amount = amount,
		ReasonCode = reasonCode,
		Timestamp = os.time(),
	})
	while #state.History > config.MaximumHistory do
		table.remove(state.History)
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	local after = self:_summary(state)
	after.LevelsGained = math.max(0, after.Level - before.Level)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		CharacterId = characterId,
		Action = "Progression.XPGranted",
		Target = trackId,
		Metadata = { Amount = amount, ReasonCode = reasonCode, Level = after.Level },
	})
	local hud = self:GetPublicHud(player)
	if hud then
		hud.Grant = { Amount = amount, TrackId = trackId, LevelsGained = after.LevelsGained }
		self.event:FireClient(player, hud)
	end
	return after, nil
end

function ProgressionService:Destroy() end

return ProgressionService
