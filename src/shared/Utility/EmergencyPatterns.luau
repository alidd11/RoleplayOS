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

-- Interprets one lamp module's already-required data.
--
-- Pulled apart from the Instance/require plumbing below it so the actual shape
-- check -- what makes a table a lamp rather than a spacer or garbage -- can be
-- tested directly with plain tables instead of live ModuleScripts. Roblox will
-- not let a runtime script set another script's Source, so a fixture module
-- with fabricated pattern data is not something a test can build.
--
-- A vehicle's kit ships one of these for every position on the bar, including
-- spacers that mark a gap and carry no patternData at all. Malformed or absent
-- data returns nil rather than erroring, because one bad export must cost that
-- lamp, not the whole stage.
function EmergencyPatterns.lampFromData(data: any, fallbackName: string?): LampPattern?
	if type(data) ~= "table" then
		return nil
	end
	local steps = data.patternData
	if type(steps) ~= "table" or #steps == 0 then
		return nil
	end
	return {
		Name = data.lightName or fallbackName or "",
		Steps = steps,
	}
end

-- Reads one lamp's module.
--
-- Wrapped, because these are ModuleScripts that came in with a bought kit and a
-- malformed one must cost that lamp rather than the whole lightbar.
local function readLamp(module: ModuleScript): LampPattern?
	local ok, data = pcall(require, module)
	if not ok then
		return nil
	end
	return EmergencyPatterns.lampFromData(data, module.Name)
end

-- The step spacing a stage runs at, from its Tempo child if it has one.
--
-- Extracted for the same reason lampFromData is: it is a pure conversion, and
-- testing it should not require building a Configuration and an IntValue to
-- prove that a missing one falls back to the default.
function EmergencyPatterns.tempoSeconds(milliseconds: number?): number
	-- Held in seconds, because everything that will step this counts in
	-- seconds and converting once here is better than at every tick.
	return math.max(milliseconds or EmergencyPatterns.DefaultTempo, 1) / 1000
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
	local milliseconds = if tempo and tempo:IsA("IntValue") then tempo.Value else nil
	return {
		Name = container.Name,
		TempoSeconds = EmergencyPatterns.tempoSeconds(milliseconds),
		Lamps = lamps,
		Length = length,
	}
end

-- The standard five names every kit in this fleet ships, in case a vehicle's
-- own EasyLS_Config cannot be read at all. Each vehicle was tuned with its own
-- shades of these -- reds and blues that are visibly different car to car --
-- so this is a fallback for a broken export, not the palette itself.
EmergencyPatterns.DefaultColours = {
	Red = Color3.fromRGB(220, 60, 50),
	Blue = Color3.fromRGB(90, 115, 210),
	White = Color3.fromRGB(180, 185, 230),
	Amber = Color3.fromRGB(255, 140, 100),
	Green = Color3.fromRGB(0, 170, 127),
}

-- A vehicle's own colour names, read from the config module it was exported
-- with. Wrapped for the same reason readLamp is: this is third-party code and
-- a vehicle whose config fails to require must still light with something
-- rather than take the whole kit down.
local function readColours(remote: Instance): { [string]: Color3 }
	local config = remote:FindFirstChild("EasyLS_Config")
	if not config or not config:IsA("ModuleScript") then
		return EmergencyPatterns.DefaultColours
	end
	local ok, settings = pcall(require, config)
	if not ok or type(settings) ~= "table" or type(settings.brickLightColors) ~= "table" then
		return EmergencyPatterns.DefaultColours
	end
	return settings.brickLightColors
end

-- The transparency a lamp is shown at once it is lit.
--
-- EasyLS ships every lamp fully transparent -- its own initialize() runs
-- lightOff on the whole bar before anything else, as the resting state a
-- pattern lights it out of -- so a lamp this engine merely recolours and
-- never un-hides stays invisible regardless of what colour it was set to.
-- Each kit tunes its own value, generally short of fully opaque so the lens
-- keeps some glow rather than reading as a solid disc.
EmergencyPatterns.DefaultOnTransparency = 0.2

local function readOnTransparency(remote: Instance): number
	local config = remote:FindFirstChild("EasyLS_Config")
	if not config or not config:IsA("ModuleScript") then
		return EmergencyPatterns.DefaultOnTransparency
	end
	local ok, settings = pcall(require, config)
	if
		not ok
		or type(settings) ~= "table"
		or type(settings.neonLightOnTransparency) ~= "number"
	then
		return EmergencyPatterns.DefaultOnTransparency
	end
	return settings.neonLightOnTransparency
end

-- Every lamp name any stage on this vehicle refers to, matched against a
-- physical part under LightsParent.
--
-- The parts are not direct children of LightsParent -- they sit nested inside
-- group models such as Front, Rear and Reds, named for the side of the car
-- rather than the lamp -- so each name is searched for recursively rather than
-- assumed to be one level down.
local function collectLampParts(
	lightsParent: Instance?,
	stages: { [string]: Stage }
): { [string]: BasePart }
	local parts: { [string]: BasePart } = {}
	if not lightsParent then
		return parts
	end
	for _, stage in stages do
		for _, lamp in stage.Lamps do
			if not parts[lamp.Name] then
				local found = lightsParent:FindFirstChild(lamp.Name, true)
				if found and found:IsA("BasePart") then
					parts[lamp.Name] = found
				end
			end
		end
	end
	return parts
end

export type Kit = {
	Remote: Instance,
	LightsParent: Instance?,
	Stages: { [string]: Stage },
	Colours: { [string]: Color3 },
	-- Every lamp any stage names, matched to the part it actually lights.
	-- A name with no match here belongs to a stage that cannot be driven --
	-- see canAdopt.
	Lamps: { [string]: BasePart },
	-- Transparency a lamp is painted at while lit. See readOnTransparency.
	OnTransparency: number,
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
	local lightsParent = if parent and parent:IsA("ObjectValue") then parent.Value else nil
	return {
		Remote = remote,
		LightsParent = lightsParent,
		Stages = stages,
		Colours = readColours(remote),
		Lamps = collectLampParts(lightsParent, stages),
		OnTransparency = readOnTransparency(remote),
	}
end

-- Whether a kit is complete enough to drive.
--
-- Refused rather than partially adopted, the same rule the road lighting
-- replacement follows: taking over a vehicle silences the scripts that light
-- it, so a kit with no lights parent -- five in the fleet, at last survey --
-- or one whose lamp names matched nothing under it would be left with nothing
-- driving it at all.
function EmergencyPatterns.canAdopt(kit: Kit): boolean
	return kit.LightsParent ~= nil and next(kit.Lamps) ~= nil
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
