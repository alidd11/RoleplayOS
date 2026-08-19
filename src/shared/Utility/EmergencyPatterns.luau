--!strict

-- Reads the flash patterns a vehicle's lightbar was authored with.
--
-- This is the first piece of replacing EasyLS, the bought emergency-lighting kit.
-- It reads only; nothing drives lamps from it yet, so it changes no behaviour on
-- its own.
--
-- The kit's data is worth keeping and its engine is not. Every vehicle carries
-- its patterns as a declarative table -- one entry per step per lamp -- and those
-- were authored per vehicle by whoever built it. Re-authoring them is not on the
-- table, so the replacement engine reads the existing shape exactly as it stands
-- and no vehicle needs re-exporting, which is the same bargain that made the road
-- lighting replacement safe.
--
-- The engine being replaced is 601 lines, but very little of that is pattern
-- logic: the rest is neon and texture lighting modes, an addon system, a signal
-- implementation and a licence check. What actually matters is below.
--
-- The shape, read off the Peugeot Van:
--
--     EasyLS_Remote
--       LightsParent  ObjectValue -> Body.ELS_Related.Lightbar
--       Patterns      Configuration
--         Stage1      Configuration, Tempo = 900
--           F1        ModuleScript -> { lightName = "F1", patternData = {...} }
--           F2, F3, RR1, ...
--         Stage2, Stage3
--         DirectorFlash, DirectorLeft, DirectorRight, DirectorSplit
--
-- `patternData` holds one entry per step. A colour name lights that lamp in that
-- colour on that step and `false` leaves it dark, so a pattern is a strip of
-- instructions the engine walks at `Tempo` milliseconds a step.

local EmergencyPatterns = {}

-- The main stages, in the order the control head cycles them.
EmergencyPatterns.Stages = { "Stage1", "Stage2", "Stage3" }

-- The director patterns, which are the rear arrow board rather than the bar.
EmergencyPatterns.DirectorStages =
	{ "DirectorFlash", "DirectorLeft", "DirectorRight", "DirectorSplit" }

-- Fallback step spacing, in milliseconds, for a stage with no Tempo of its own.
EmergencyPatterns.DefaultTempo = 900

export type LampPattern = {
	Name: string,
	-- One entry per step: a colour name, or false for dark.
	Steps: { string | boolean },
}

export type Stage = {
	Name: string,
	TempoSeconds: number,
	Lamps: { LampPattern },
	-- The longest strip in this stage. Shorter lamps wrap, so a lamp with ten
	-- steps in a thirty step stage repeats three times rather than going dark for
	-- two thirds of the cycle.
	Length: number,
}

-- Reads one lamp's module.
--
-- Wrapped, because these are ModuleScripts that came in with a bought kit and a
-- malformed one must cost that lamp rather than the whole lightbar.
local function readLamp(module: ModuleScript): LampPattern?
	local ok, data = pcall(require, module)
	if not ok or type(data) ~= "table" then
		return nil
	end
	local steps = (data :: any).patternData
	if type(steps) ~= "table" or #steps == 0 then
		return nil
	end
	return {
		Name = (data :: any).lightName or module.Name,
		Steps = steps,
	}
end

-- Reads one stage: its tempo and every lamp strip inside it.
function EmergencyPatterns.readStage(container: Instance): Stage?
	local lamps: { LampPattern } = {}
	local length = 0
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") then
			local lamp = readLamp(child)
			if lamp then
				table.insert(lamps, lamp)
				if #lamp.Steps > length then
					length = #lamp.Steps
				end
			end
		end
	end
	if #lamps == 0 then
		return nil
	end
	local tempo = container:FindFirstChild("Tempo")
	local milliseconds = if tempo and tempo:IsA("IntValue")
		then tempo.Value
		else EmergencyPatterns.DefaultTempo
	return {
		Name = container.Name,
		-- Held in seconds, because everything that will step this counts in
		-- seconds and converting once here is better than at every tick.
		TempoSeconds = math.max(milliseconds, 1) / 1000,
		Lamps = lamps,
		Length = length,
	}
end

export type Kit = {
	Remote: Instance,
	LightsParent: Instance?,
	Stages: { [string]: Stage },
}

-- Everything one vehicle's lightbar was authored with.
--
-- Returns nil for a vehicle carrying no kit, which is most of the fleet: only the
-- emergency ones have a lightbar, and a civilian car must not be treated as one
-- that simply has its lights off.
function EmergencyPatterns.read(vehicle: Instance): Kit?
	local remote = vehicle:FindFirstChild("EasyLS_Remote", true)
	if not remote then
		return nil
	end
	local patterns = remote:FindFirstChild("Patterns")
	if not patterns then
		return nil
	end
	local stages: { [string]: Stage } = {}
	for _, child in patterns:GetChildren() do
		local stage = EmergencyPatterns.readStage(child)
		if stage then
			stages[child.Name] = stage
		end
	end
	if next(stages) == nil then
		return nil
	end
	local parent = remote:FindFirstChild("LightsParent")
	return {
		Remote = remote,
		LightsParent = if parent and parent:IsA("ObjectValue") then parent.Value else nil,
		Stages = stages,
	}
end

-- What a lamp should be doing at a given moment.
--
-- The step is derived from a clock rather than counted, for the reason the road
-- lighting flash is: every vehicle on the server then shares one timebase, a
-- pattern cannot drift, and nothing has to be unwound when a stage changes.
-- Shorter strips wrap within the stage's length.
function EmergencyPatterns.colourAt(lamp: LampPattern, stage: Stage, clock: number): string?
	local step = math.floor(clock / stage.TempoSeconds) % math.max(stage.Length, 1)
	local entry = lamp.Steps[(step % #lamp.Steps) + 1]
	return if type(entry) == "string" then entry else nil
end

return EmergencyPatterns
