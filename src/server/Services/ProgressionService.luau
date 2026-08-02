--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LevelProgression = require(ReplicatedStorage.RoleplayOS.Shared.LevelProgression)

local ProgressionService = {}

function ProgressionService:Init(context: any)
	self.context = context
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
	return after, nil
end

function ProgressionService:Destroy() end

return ProgressionService
