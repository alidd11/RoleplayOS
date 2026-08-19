--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EmergencyPatterns = require(ReplicatedStorage.RoleplayOS.Shared.EmergencyPatterns)

-- The engine that replaces EasyLS, the bought emergency-lighting kit.
--
-- EmergencyLightsService already silences the kit's own server script on
-- adoption -- see its Adopt -- which stops it fighting this over the same
-- lamps, but silencing it also means nothing lights the bar at all. This is
-- what lights it instead, reading the exact declarative pattern data the
-- vehicle was authored with (see EmergencyPatterns) rather than re-authoring
-- anything.
--
-- Server authoritative, the same as VehicleLightingService and for the same
-- reason: writing Color3 and Material on the server replicates to every
-- observer for free, so there is no per-client render loop to keep in sync
-- and a vehicle nobody is near costs nothing extra to run.
local EmergencyLightPatternService = {
	Critical = false,
	connections = {},
	-- Live state per vehicle, keyed by the model.
	vehicles = {},
}

function EmergencyLightPatternService:Init(context: any)
	self.context = context
end

-- A lamp name against every stage that names it, built once at adoption so
-- the paint loop is a table lookup rather than a scan of every lamp in the
-- active stage on every tick for every vehicle.
local function indexLamps(
	stages: { [string]: EmergencyPatterns.Stage }
): { [string]: { [string]: EmergencyPatterns.LampPattern } }
	local index = {}
	for stageName, stage in stages do
		local byName = {}
		for _, lamp in stage.Lamps do
			byName[lamp.Name] = lamp
		end
		index[stageName] = byName
	end
	return index
end

-- Takes over a vehicle's lightbar. Called alongside EmergencyLightsService's
-- own adoption, wherever a vehicle is created or a parked one is claimed.
--
-- Refused rather than partially adopted, on the same rule the road lighting
-- replacement follows -- see EmergencyPatterns.canAdopt for why.
function EmergencyLightPatternService:Adopt(vehicle: Instance)
	if self.vehicles[vehicle] then
		return
	end
	local kit = EmergencyPatterns.read(vehicle)
	if not kit or not EmergencyPatterns.canAdopt(kit) then
		return
	end
	-- Recorded before this ever paints a lamp, so a stage that stops covering
	-- one puts it back exactly as it was built rather than to a guessed off
	-- colour.
	local original = {}
	for name, part in kit.Lamps do
		original[name] =
			{ Color = part.Color, Material = part.Material, Transparency = part.Transparency }
	end
	-- Which of the kit's own Stage1/Stage2/Stage3 this vehicle actually
	-- authored, in order. Most of the fleet has only Stage1 -- the framework's
	-- own Stage number still runs 0..settings.Stages regardless, so a numeric
	-- Stage is mapped against however many of these actually exist rather than
	-- against a fixed index into all three. Without this, RESPONSE (the
	-- framework's top level) landed on the kit's empty Stage2 on a vehicle that
	-- only authored Stage1, and the bar went dark at the exact moment it was
	-- supposed to be at its brightest, while AT SCENE -- one level down --
	-- correctly lit the only pattern the vehicle has.
	local availableMainStages = {}
	for _, name in EmergencyPatterns.Stages do
		if kit.Stages[name] then
			table.insert(availableMainStages, name)
		end
	end
	self.vehicles[vehicle] = {
		Kit = kit,
		Original = original,
		StageIndex = indexLamps(kit.Stages),
		AvailableMainStages = availableMainStages,
		-- What each lamp is currently showing: a colour name, or false for
		-- dark/original. Forces the first paint to actually write, the same
		-- reason VehicleLightingService's Painted starts nil.
		Painted = {},
	}
	vehicle.Destroying:Once(function()
		self.vehicles[vehicle] = nil
	end)
	local lampCount = 0
	for _ in kit.Lamps do
		lampCount += 1
	end
	self.context.Logger:Info("EasyLS pattern engine adopted", {
		Vehicle = vehicle.Name,
		Lamps = lampCount,
	})
end

-- What a lamp should show right now, main bar first and the director board
-- second. A name only ever appears in one of the two on any kit surveyed so
-- far, but checking both rather than assuming it keeps a lamp that did double
-- duty from going dark simply because the main stage does not claim it.
local function desiredColour(
	state: any,
	name: string,
	mainStageName: string?,
	directorStageName: string?,
	clock: number
): string?
	local mainStage = mainStageName and state.Kit.Stages[mainStageName]
	local mainLamp = mainStageName
		and state.StageIndex[mainStageName]
		and state.StageIndex[mainStageName][name]
	if mainStage and mainLamp then
		local colour = EmergencyPatterns.colourAt(mainLamp, mainStage, clock)
		if colour then
			return colour
		end
	end
	local directorStage = directorStageName and state.Kit.Stages[directorStageName]
	local directorLamp = directorStageName
		and state.StageIndex[directorStageName]
		and state.StageIndex[directorStageName][name]
	if directorStage and directorLamp then
		return EmergencyPatterns.colourAt(directorLamp, directorStage, clock)
	end
	return nil
end

-- Applies the desired colour to every lamp this vehicle has, writes guarded
-- on change for the reason VehicleLightingService's _paint gives: this runs
-- every frame for every adopted vehicle, and an unconditional write dirties
-- replication even when nothing actually changed.
function EmergencyLightPatternService:_paint(vehicle: Instance)
	local state = self.vehicles[vehicle]
	if not state then
		return
	end
	local settings = self.context.Configuration.EmergencyLighting
	local stageNumber = vehicle:GetAttribute(settings.StageAttribute)
	local available = state.AvailableMainStages
	local mainStageName = if type(stageNumber) == "number"
			and stageNumber >= 1
			and #available > 0
		then available[math.min(math.floor(stageNumber), #available)]
		else nil
	local directorName = vehicle:GetAttribute(settings.DirectorAttribute)
	local directorStageName = if type(directorName) == "string" and directorName ~= ""
		then directorName
		else nil
	local clock = os.clock()
	for name, part in state.Kit.Lamps do
		local colour = desiredColour(state, name, mainStageName, directorStageName, clock)
		if state.Painted[name] ~= colour then
			state.Painted[name] = colour
			if colour then
				local rgb = state.Kit.Colours[colour]
				if rgb then
					part.Color = rgb
					part.Material = Enum.Material.Neon
					-- EasyLS ships every lamp fully transparent as the rest
					-- state a pattern lights it out of. Recolouring alone
					-- left it invisible: this is what actually shows it.
					part.Transparency = state.Kit.OnTransparency
				end
			else
				local original = state.Original[name]
				part.Color = original.Color
				part.Material = original.Material
				part.Transparency = original.Transparency
			end
			local light = part:FindFirstChildWhichIsA("Light")
			if light and light.Enabled ~= (colour ~= nil) then
				light.Enabled = colour ~= nil
			end
		end
	end
end

function EmergencyLightPatternService:Start()
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function()
			for vehicle in self.vehicles do
				if vehicle.Parent then
					self:_paint(vehicle)
				else
					self.vehicles[vehicle] = nil
				end
			end
		end)
	)
end

function EmergencyLightPatternService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.vehicles)
end

return EmergencyLightPatternService
