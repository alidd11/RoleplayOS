--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VehicleLighting = require(ReplicatedStorage.RoleplayOS.Shared.VehicleLighting)

-- Road lighting, owned by the framework rather than by the bought kit.
--
-- See the shared VehicleLighting module for what was wrong with the kit this
-- replaces. The short version is that its remote was unvalidated, its hazards
-- were broken, and it spent a script per lamp per vehicle animating itself.
--
-- Everything here is server authoritative. The client sends an intent -- "toggle
-- the left indicator" -- and never a state, so a exploiting client can at worst
-- toggle its own vehicle's lights, which is a thing it can already do by
-- pressing the key.
local VehicleLightingService = {
	-- A vehicle with no lamps is a vehicle with no lamps. Never a reason to stop
	-- the server starting.
	Critical = false,
	connections = {},
	-- Live state per vehicle, keyed by the model.
	vehicles = {},
}

function VehicleLightingService:Init(context: any)
	self.context = context
end

-- Turns off the kit's own scripts for a vehicle.
--
-- Disabled rather than destroyed, and only on the live clone: the template in
-- ServerStorage is a $path Rojo owns, so a change there would be overwritten on
-- the next sync and would need an .rbxm re-export to persist. Leaving the
-- originals in place also means a vehicle can be inspected to see what it
-- shipped with.
--
-- Three things to silence. The LocalScript holding the keybinds, the server
-- Script holding the state, and the per-group animator that would otherwise
-- fight us for control of the same lamps.
--
-- The animators are found by position rather than by name. They are called
-- Halogen on the cars, "LED Handler" on a bike's indicators and Control on the
-- same bike's brake lamp, and a name list would have to grow with every kit --
-- while blanket-disabling anything called Control would reach scripts that have
-- nothing to do with lighting. A script sitting directly inside a lamp group we
-- have taken over is unambiguously that group's animator.
local VEHICLE_LEVEL_SCRIPTS = { LightAddon = true }

function VehicleLightingService:_silenceKit(vehicle: Instance, lamps: any): number
	local silenced = 0
	for _, group in lamps do
		for _, lamp in group do
			for _, child in lamp.Model:GetChildren() do
				if child:IsA("BaseScript") and not child.Disabled then
					child.Disabled = true
					silenced += 1
				end
			end
		end
	end
	for _, descendant in vehicle:GetDescendants() do
		if
			descendant:IsA("BaseScript")
			and VEHICLE_LEVEL_SCRIPTS[descendant.Name]
			and not descendant.Disabled
		then
			descendant.Disabled = true
			silenced += 1
		end
	end
	-- The handler sits under a RemoteEvent named for the kit. Taking the remote
	-- away as well closes the hole where any player on the server could fire it
	-- for somebody else's car.
	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("RemoteEvent") and descendant.Name == "SmeersLightsHandler" then
			descendant:Destroy()
			silenced += 1
		end
	end
	return silenced
end

-- Takes over a vehicle's lighting. Called by the spawner for every vehicle it
-- creates, alongside the emergency-lights adoption beside it.
function VehicleLightingService:Adopt(vehicle: Instance)
	local lamps = VehicleLighting.collect(vehicle)
	-- Refused rather than partially adopted. Silencing the kit takes away what
	-- sets every lamp value on the vehicle, so taking over half of one leaves the
	-- other half dark with nothing driving it.
	if not VehicleLighting.canAdopt(lamps) then
		return
	end
	local silenced = self:_silenceKit(vehicle, lamps)
	self.vehicles[vehicle] = {
		Lamps = lamps,
		Stage = "Off",
		Left = false,
		Right = false,
		Hazards = false,
		Brakes = false,
		Reverse = false,
		-- Forces the first paint, so a vehicle adopted with its lenses left lit by
		-- the kit is put into a known state rather than inheriting one.
		Painted = nil,
	}
	vehicle.Destroying:Once(function()
		self.vehicles[vehicle] = nil
	end)
	self:_publish(vehicle, self.vehicles[vehicle])
	self:_paint(vehicle, true)
	self.context.Logger:Info("Vehicle lighting adopted", {
		Vehicle = vehicle.Name,
		Groups = self:_groupCount(lamps),
		KitScriptsSilenced = silenced,
	})
end

function VehicleLightingService:_groupCount(lamps: any): number
	local n = 0
	for _ in lamps do
		n += 1
	end
	return n
end

-- Which lamp groups should be lit right now.
function VehicleLightingService:_desired(state: any, flashOn: boolean): { [string]: boolean }
	-- Cloned, because the stage tables in the shared module are the definition of
	-- what a stage means. Writing the indicators into one would rewrite that
	-- definition for every vehicle on the server.
	local lit: { [string]: boolean } = table.clone(VehicleLighting.StageLamps[state.Stage] or {})
	-- Hazards drive both sides and override the individual indicators, which is
	-- what the switch does in a real car.
	local left = state.Hazards or state.Left
	local right = state.Hazards or state.Right
	lit.Left = left and flashOn
	lit.Right = right and flashOn
	lit.Brakes = state.Brakes
	lit.Reverse = state.Reverse
	return lit
end

-- Applies the desired state to the actual lamp parts.
--
-- Writes are guarded on change. This runs every frame for every vehicle with its
-- lights on, and setting Transparency on a part that already has that value
-- still dirties it for replication.
function VehicleLightingService:_paint(vehicle: Instance, force: boolean?)
	local state = self.vehicles[vehicle]
	if not state then
		return
	end
	local flashOn = VehicleLighting.flashOn(os.clock())
	local desired = self:_desired(state, flashOn)
	local painted = state.Painted or {}
	for name, group in state.Lamps do
		local want = desired[name] == true
		if force or painted[name] ~= want then
			painted[name] = want
			for _, lamp in group do
				-- The BoolValue stays the contract. The cluster reads it, and so may
				-- anything else authored against the kit's shape.
				if lamp.State and lamp.State.Value ~= want then
					lamp.State.Value = want
				end
				for _, part in lamp.Parts do
					part.Transparency = if want
						then VehicleLighting.LitTransparency
						else VehicleLighting.UnlitTransparency
					local light = part:FindFirstChildWhichIsA("Light")
					if light and light.Enabled ~= want then
						light.Enabled = want
					end
				end
			end
		end
	end
	state.Painted = painted
end

-- The driver of a vehicle, or nil.
local function driverOf(vehicle: Instance): Player?
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	local occupant = seat and seat.Occupant
	return if occupant then Players:GetPlayerFromCharacter(occupant.Parent) else nil
end

-- The vehicle a player is driving, or nil. This is the authorisation check: a
-- request only ever reaches the car its sender is sitting in.
function VehicleLightingService:_vehicleFor(player: Player): Instance?
	for vehicle in self.vehicles do
		if vehicle.Parent and driverOf(vehicle) == player then
			return vehicle
		end
	end
	return nil
end

-- Handles one request from a driver. Intents only, never states.
function VehicleLightingService:Set(player: Player, payload: any): (boolean, string?)
	local vehicle = self:_vehicleFor(player)
	if not vehicle then
		return false, "NOT_DRIVING"
	end
	local state = self.vehicles[vehicle]
	local action = payload.Action
	if action == "IndicateLeft" then
		state.Left = not state.Left
		-- Cancels the other side, as a stalk does.
		if state.Left then
			state.Right = false
		end
	elseif action == "IndicateRight" then
		state.Right = not state.Right
		if state.Right then
			state.Left = false
		end
	elseif action == "Hazards" then
		state.Hazards = not state.Hazards
		if state.Hazards then
			state.Left, state.Right = false, false
		end
	elseif action == "Stage" then
		state.Stage = VehicleLighting.nextStage(state.Stage)
	elseif action == "Off" then
		state.Left, state.Right, state.Hazards = false, false, false
		state.Stage = "Off"
	else
		return false, "UNKNOWN_ACTION"
	end
	self:_publish(vehicle, state)
	self:_paint(vehicle, true)
	return true, nil
end

-- Publishes the parts of the state a client cannot infer from the lamps.
--
-- The kit kept its stage in a server-side local with no getter, so nothing could
-- ever display which setting was selected. An attribute costs nothing and means
-- the cluster can show it.
-- Named for road lighting specifically, not "lights".
--
-- The obvious name, RoleplayOSLightStage, is already taken: it is the emergency
-- lighting stage, set by EmergencyLightsService on the same models. Publishing
-- the headlight setting under it would have overwritten the lightbar's stage
-- every time a driver touched the indicators, on exactly the vehicles where both
-- systems run. Found it because a freshly spawned van reported stage 0 before
-- this service had published anything.
function VehicleLightingService:_publish(vehicle: Instance, state: any)
	vehicle:SetAttribute("RoleplayOSRoadLightStage", state.Stage)
	vehicle:SetAttribute("RoleplayOSRoadHazards", state.Hazards)
end

-- Brake and reversing lamps, taken from the chassis rather than from the driver.
--
-- The kit did this on the client with a nested busy loop that ran for as long as
-- the brake was held. Both are simply functions of the seat and the gear, so
-- they are read here on the same step as everything else.
function VehicleLightingService:_readChassis(vehicle: Instance, state: any)
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat then
		return
	end
	state.Brakes = seat.Throttle < -0.05
	local settings = self.context.Configuration.Chassis
	local values = vehicle:FindFirstChild(settings.ValuesFolderName, true)
	local gear = values and values:FindFirstChild(settings.GearValueName)
	state.Reverse = gear ~= nil and (gear :: any).Value == -1
end

function VehicleLightingService:Start()
	-- One loop for every vehicle on the server, rather than one per lamp per
	-- vehicle. At a hundred and five scripts across the fleet the kit's approach
	-- was the single largest script count in the place.
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function()
			for vehicle, state in self.vehicles do
				if vehicle.Parent then
					self:_readChassis(vehicle, state)
					self:_paint(vehicle)
				else
					self.vehicles[vehicle] = nil
				end
			end
		end)
	)
end

function VehicleLightingService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.vehicles)
end

return VehicleLightingService
