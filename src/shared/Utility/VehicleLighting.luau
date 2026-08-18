--!strict

-- Road lighting: indicators, hazards, sidelights, headlights, main beam, brake
-- lamps and reversing lamps.
--
-- This replaces the bought "Smeers" light addon that shipped inside every
-- vehicle. That kit was three separate pieces per car -- a LocalScript holding
-- the keybinds, a server Script holding the state, and one Halogen script per
-- lamp group holding its own animation -- which came to seven scripts a vehicle
-- and a hundred and five across the fleet, each an identical copy.
--
-- Replacing it is worth doing on defects alone, not only on tidiness:
--
--   * Its remote validated nothing. `event.OnServerEvent` accepted a toggle from
--     any player on the server, not just whoever was driving, so anybody could
--     flash anybody else's indicators from anywhere on the map.
--   * Hazards were broken outright. The handler wrote to Body.Lights.Hazards,
--     which does not exist on these models -- the value is authored elsewhere --
--     so pressing X threw a server error instead of doing anything.
--   * Hazards never alternated anyway. It set both indicators on and left them,
--     so both sides blinked on their own independent timers.
--   * Its stage counter was a local on the server with no way to read it, the
--     same fault the ELS kit has, so no interface could show what was selected.
--   * Each indicator animated itself with a `repeat ... wait(0.35)` loop started
--     from a Changed handler, so toggling quickly left several loops running over
--     each other on the same lamp.
--   * Braking ran a nested `repeat ... wait(0.05)` busy loop on the client for
--     the duration of every brake application.
--
-- The data shape is deliberately kept. Each lamp group is a model under
-- Body.Lights with a BoolValue called `on` and a folder of parts called G1, and
-- this system keeps writing that BoolValue. Anything already reading it -- the
-- driver's cluster does -- carries on working untouched, and no vehicle has to
-- be re-exported for the change.

local VehicleLighting = {}

-- What each lamp group inside a Lights container is called, mapped to our name.
--
-- Found structurally rather than by path. It began as a list of paths --
-- Body.Lights, Misc.TK.Boot.Lights -- which is wrong for the same reason
-- hardcoding any of this is wrong: the bikes keep their front indicators,
-- headlight and main beam under FrontSection.Wheel.WheelFixed.Stand.Lights, and
-- a path list found the rear lamps only. That mattered a great deal, because
-- taking over a vehicle also silences the kit script that sets these values: a
-- half-found bike had its front lights left with nothing driving them at all.
--
-- Any container called Lights, anywhere in the vehicle, is searched.
VehicleLighting.GroupNames = {
	Left = "Left",
	Right = "Right",
	Headlight = "Headlight",
	Highlight = "MainBeam",
	DRL = "Sidelight",
	Brakes = "Brakes",
	Reverse = "Reverse",
}

-- Groups that flash rather than sit steady.
VehicleLighting.Flashing = { Left = true, Right = true }

-- The light-stage ring the L key walks through.
--
-- Off, sidelights, dipped headlights, main beam, and round to off. The original
-- had five states with two of them identical and a first press that skipped one,
-- which is why the first press of L appeared to do nothing on some cars.
VehicleLighting.Stages = { "Off", "Sidelight", "Headlight", "MainBeam" }

-- What each stage lights.
VehicleLighting.StageLamps = {
	Off = {},
	Sidelight = { Sidelight = true },
	Headlight = { Sidelight = true, Headlight = true },
	MainBeam = { Sidelight = true, Headlight = true, MainBeam = true },
}

-- Indicator timing. UK regulations put a road vehicle's indicator between 60 and
-- 120 flashes a minute; 90 is the middle and what most cars use.
VehicleLighting.FlashesPerMinute = 90

-- What a lamp group calls the folder holding its lens parts.
--
-- Cars use G1. The bikes use LED for their indicators and G1 for their brake
-- lamp, in the same vehicle. Checking only G1 found the bike's brake light and
-- neither of its indicators, which mattered: the service would then have silenced
-- the bike's own lighting script while replacing only a third of what it did,
-- leaving the indicators dead.
VehicleLighting.PartFolders = { "G1", "LED" }

-- Lit and unlit transparency for a lamp lens. Not fully opaque when lit, because
-- these lenses are emissive meshes and a little transparency is what makes them
-- read as glowing rather than as painted plastic.
VehicleLighting.LitTransparency = 0.2
VehicleLighting.UnlitTransparency = 1

export type Lamp = {
	Model: Instance,
	State: BoolValue?,
	Parts: { BasePart },
}

-- Every lamp group a vehicle actually has, keyed by our name for it.
--
-- A vehicle missing a group simply does not get that entry, which is the normal
-- case: not every car has a separate main beam or a boot lid set, and a bike has
-- almost none of this.
function VehicleLighting.collect(vehicle: Instance): { [string]: { Lamp } }
	local found: { [string]: { Lamp } } = {}
	for _, container in vehicle:GetDescendants() do
		if container.Name ~= "Lights" then
			continue
		end
		for _, model in container:GetChildren() do
			local name = VehicleLighting.GroupNames[model.Name]
			if not name then
				continue
			end
			local parts: { BasePart } = {}
			for _, folderName in VehicleLighting.PartFolders do
				local group = model:FindFirstChild(folderName)
				for _, child in (if group then group:GetChildren() else {}) do
					if child:IsA("BasePart") then
						table.insert(parts, child)
					end
				end
			end
			if #parts > 0 then
				local state = model:FindFirstChild("on")
				found[name] = found[name] or {}
				table.insert(found[name], {
					Model = model,
					State = if state and state:IsA("BoolValue") then state else nil,
					Parts = parts,
				})
			end
		end
	end
	return found
end

-- Is this a vehicle we are able to take over?
--
-- Only when both indicators were found. Adopting a vehicle silences the kit
-- script that sets every one of its lamp values, so a partial match does not
-- degrade gracefully -- it leaves the lamps we did not find with nothing driving
-- them. The indicators are the right test because they are what the controls
-- exist for: a vehicle whose indicators we cannot drive is one we should not be
-- taking the keys of at all.
--
-- The Honda scooter is the case this protects. It names its groups Brake,
-- Headlights, Indicators and Fog, so almost nothing matches, and it keeps its own
-- lighting kit intact rather than being half-adopted and left dark.
function VehicleLighting.canAdopt(lamps: { [string]: { Lamp } }): boolean
	return lamps.Left ~= nil and lamps.Right ~= nil
end

-- Whether a flashing lamp should be lit at this moment.
--
-- Driven from a clock rather than from a per-lamp loop, so every indicator on
-- the server is in phase with every other and a vehicle that toggles quickly
-- cannot end up with two animations fighting over one lamp. Hazards look right
-- for free: both sides read the same clock, so they flash together.
function VehicleLighting.flashOn(clock: number): boolean
	local period = 60 / VehicleLighting.FlashesPerMinute
	return (clock % period) < (period / 2)
end

-- The stage after this one.
function VehicleLighting.nextStage(current: string?): string
	local stages = VehicleLighting.Stages
	for index, name in stages do
		if name == current then
			return stages[(index % #stages) + 1]
		end
	end
	return stages[2]
end

return VehicleLighting
