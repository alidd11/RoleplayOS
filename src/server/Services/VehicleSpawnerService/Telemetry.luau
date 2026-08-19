--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local FuelConsumption = require(ReplicatedStorage.RoleplayOS.Shared.FuelConsumption)
local RigMechanics = require(script.Parent.RigMechanics)

return function(VehicleSpawnerService)
	function VehicleSpawnerService:_beginTelemetry(
		player: Player,
		vehicle: Model,
		vehicleId: string?,
		mileage: number
	)
		local pivot = vehicle:GetPivot().Position
		self.telemetry[player.UserId] = {
			Vehicle = vehicle,
			VehicleId = vehicleId,
			Fuel = 100,
			Mileage = mileage,
			LastPosition = pivot,
			-- What was last written to the profile, so a tick that moved nothing does
			-- not mark the session dirty.
			PersistedFuel = nil,
			PersistedMileage = nil,
		}
	end

	-- Banks the current reading onto the owner's profile.
	--
	-- Rate limited by the caller except on the final call, which happens as the
	-- vehicle is destroyed and must not be skipped.

	function VehicleSpawnerService:_persistTelemetry(userId: number, force: boolean): boolean
		local state = self.telemetry[userId]
		if not state or type(state.VehicleId) ~= "string" then
			return false
		end
		if
			not force
			and state.PersistedFuel == state.Fuel
			and state.PersistedMileage == state.Mileage
		then
			return false
		end
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			return false
		end
		local ownership = self.context.Services:Get("VehicleOwnershipService")
		local fuel = if self.context.Configuration.VehicleData.FuelEnabled then state.Fuel else nil
		local wrote = ownership:RecordTelemetry(player, state.VehicleId, fuel, state.Mileage)
		state.PersistedFuel = state.Fuel
		state.PersistedMileage = state.Mileage
		return wrote
	end

	-- Stops the engine when the tank is empty, and lets it run again once it is not.
	--
	-- Config.Chassis.EngineValueName has named this value since the config was
	-- written and nothing had ever read it. A-Chassis makes its own torque from that
	-- folder and never consults MaxSpeed, so cutting the engine is the only lever
	-- that reaches these vehicles at all.

	function VehicleSpawnerService:_setEngine(vehicle: Model, running: boolean)
		local settings = self.context.Configuration.Chassis
		local values = RigMechanics.chassisValues(vehicle, settings)
		local engine = values and values:FindFirstChild(settings.EngineValueName)
		if engine and engine:IsA("ValueBase") and (engine :: any).Value ~= running then
			(engine :: any).Value = running
		end
	end

	function VehicleSpawnerService:_consumeTick(dt: number)
		local settings = self.context.Configuration.VehicleData
		for _, state in self.telemetry do
			local vehicle = state.Vehicle
			if not vehicle or not vehicle.Parent then
				continue
			end
			local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
			local position = vehicle:GetPivot().Position
			local previous = state.LastPosition or position
			state.LastPosition = position

			-- Only bills a vehicle somebody is sitting in. A car abandoned in the road
			-- is not burning anything, and this is also what stops the loop charging for
			-- the shove a spawner gives a vehicle as it sets it down.
			if not seat or seat.Occupant == nil then
				continue
			end

			-- Horizontal only. A vehicle dropped by the spawner, or bounced by a kerb,
			-- travels vertically without going anywhere, and neither the odometer nor
			-- the tank should record that as distance.
			local moved = (Vector3.new(position.X, 0, position.Z) - Vector3.new(
				previous.X,
				0,
				previous.Z
			)).Magnitude

			local miles, burnt = FuelConsumption.tick(moved, dt, settings)
			-- The odometer runs whether or not fuel is a system here. Mileage is a
			-- property of the vehicle that the MDT and the vehicle record both read.
			state.Mileage += miles
			vehicle:SetAttribute("RoleplayOSMileage", state.Mileage)

			if settings.FuelEnabled then
				state.Fuel = math.max(state.Fuel - burnt, 0)
				vehicle:SetAttribute("RoleplayOSFuel", state.Fuel)
				self:_setEngine(vehicle, state.Fuel > settings.EmptyFuelPercent)
			end
		end
	end

	-- Takes the chassis's own gauges out of a vehicle.
	--
	-- The cluster replaces them, and two separate pieces of code were previously
	-- hiding them: VehicleUIController disabling the chassis ScreenGui, and the
	-- speedometer hiding the gauge frame within it. Neither stopped the script, which
	-- carried on writing a needle rotation and a speed string to an invisible frame
	-- on every Velocity change for as long as anybody was driving.
	--
	-- The whole gauge frame goes rather than just the script, so there is nothing
	-- left to be re-enabled by something else later. Done on the live clone only --
	-- the template is a Rojo $path and would be overwritten on the next sync.

	function VehicleSpawnerService:_removeStockGauges(vehicle: Model): number
		local names = self.context.Configuration.Chassis.StockGaugeScripts or {}
		local removed = 0
		for _, descendant in vehicle:GetDescendants() do
			if descendant:IsA("LocalScript") and table.find(names, descendant.Name) then
				-- The frame is the thing worth removing; the script rides inside it.
				local frame = descendant.Parent
				if frame and frame:IsA("GuiObject") then
					frame:Destroy()
				else
					descendant.Disabled = true
				end
				removed += 1
			end
		end
		return removed
	end
end
