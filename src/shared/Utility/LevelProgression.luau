--!strict

local LevelProgression = {}

function LevelProgression.xpForLevel(level: number, baseXp: number, growth: number): number
	if level <= 1 then
		return 0
	end
	local total = 0
	for current = 1, level - 1 do
		total += math.floor(baseXp * growth ^ (current - 1) + 0.5)
	end
	return total
end

function LevelProgression.fromXp(
	totalXp: number,
	baseXp: number,
	growth: number,
	maximumLevel: number
): any
	local safeXp = math.max(0, math.floor(totalXp))
	local level = 1
	local levelStart = 0
	local required = math.floor(baseXp + 0.5)
	while level < maximumLevel and safeXp >= levelStart + required do
		levelStart += required
		level += 1
		required = math.floor(baseXp * growth ^ (level - 1) + 0.5)
	end
	if level >= maximumLevel then
		required = 0
	end
	local current = math.max(0, safeXp - levelStart)
	return {
		Level = level,
		TotalXP = safeXp,
		CurrentLevelXP = current,
		RequiredLevelXP = required,
		Progress = if required > 0 then math.clamp(current / required, 0, 1) else 1,
		AtMaximumLevel = level >= maximumLevel,
	}
end

return table.freeze(LevelProgression)
