--!strict

-- The arithmetic behind the fuel gauge and the odometer.
--
-- Pulled out of VehicleSpawnerService so it can be tested without a running
-- server, a spawned vehicle or physics. That is not tidiness for its own sake:
-- the burn loop can only be exercised in engine by actually driving, and a
-- vehicle cannot be driven from a script -- A-Chassis is client authoritative and
-- overrides a velocity written on the server, while teleporting the model throws
-- the rider out of the seat and stops the loop counting, correctly, because it
-- only bills an occupied vehicle. Every attempt to verify the sums that way
-- measured the test rig rather than the code.
--
-- So the sums live here and are checked directly, and the service keeps only the
-- parts that genuinely need the world: reading positions, and writing attributes.

local FuelConsumption = {}

-- Studs in a mile, derived rather than invented.
--
-- At K miles per hour per stud per second, a vehicle at K mph covers one stud a
-- second, so an hour of it covers 3600 studs and one mile is 3600/K studs. With
-- the configured K of 0.626 that is about 5751.
function FuelConsumption.studsPerMile(studsPerSecondToMph: number): number
	return 3600 / math.max(studsPerSecondToMph, 0.001)
end

function FuelConsumption.miles(studs: number, studsPerSecondToMph: number): number
	if studs <= 0 then
		return 0
	end
	return studs / FuelConsumption.studsPerMile(studsPerSecondToMph)
end

-- The furthest a vehicle could honestly have travelled in one tick.
--
-- Anything beyond it is a teleport, a respawn or a physics explosion, and must
-- not be billed: it would empty a tank in one frame, and it would let somebody
-- wind mileage onto a vehicle by dying repeatedly.
--
-- This was a flat 400 studs, which is less than the 448 a vehicle covers in a
-- single two second tick at 140mph. Anybody driving quickly had all of their
-- distance discarded, so the tank stopped emptying and the odometer stopped
-- counting exactly when they were burning the most fuel. Scaling it by the tick
-- length and the top speed fixes that; the factor of two leaves room for downhill
-- runs and for a chassis overshooting its own limit, while staying far below any
-- real teleport.
function FuelConsumption.implausibleStuds(
	dtSeconds: number,
	topSpeedMph: number,
	studsPerSecondToMph: number
): number
	local studsPerSecond = topSpeedMph / math.max(studsPerSecondToMph, 0.001)
	return studsPerSecond * 2 * math.max(dtSeconds, 0)
end

-- How much of the tank a tick costs, as a percentage.
--
-- Two components, because a car burns fuel for moving and for merely running.
-- Without the idle term a vehicle left ticking over is a free generator; without
-- the distance term the gauge ignores how it is driven.
function FuelConsumption.burn(
	miles: number,
	dtSeconds: number,
	percentPerMile: number,
	percentPerIdleMinute: number
): number
	return math.max(miles, 0) * percentPerMile
		+ (math.max(dtSeconds, 0) / 60) * percentPerIdleMinute
end

-- One tick of the loop, given a displacement.
--
-- Returns the miles to add and the fuel to subtract. Distance beyond the
-- plausible limit yields nothing at all rather than being clamped, because a
-- teleport is not a very long drive: crediting the maximum for it would still be
-- crediting something that never happened.
function FuelConsumption.tick(
	studs: number,
	dtSeconds: number,
	settings: {
		StudsPerSecondToMph: number,
		FuelPercentPerMile: number,
		FuelPercentPerIdleMinute: number,
		TopSpeedMphCeiling: number,
	}
): (number, number)
	local limit = FuelConsumption.implausibleStuds(
		dtSeconds,
		settings.TopSpeedMphCeiling,
		settings.StudsPerSecondToMph
	)
	local travelled = if studs > limit then 0 else studs
	local miles = FuelConsumption.miles(travelled, settings.StudsPerSecondToMph)
	local burnt = FuelConsumption.burn(
		miles,
		dtSeconds,
		settings.FuelPercentPerMile,
		settings.FuelPercentPerIdleMinute
	)
	return miles, burnt
end

return FuelConsumption
