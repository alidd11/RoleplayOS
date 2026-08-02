# Vehicles

Dealership catalogues refer to configured vehicle IDs. Purchase revalidates catalogue membership and access, debits the configured price, then creates a GUID ownership record and generated registration. Ownership, colour, mileage, fuel, condition, insurance, tax and garage are persisted per character.

Spawning checks active character ownership, terminal distance, spawn-point clearance, cooldown and the one-active-vehicle limit before cloning a configured ServerStorage model. Clearance checks recognise existing RoleplayOS vehicles and characters in the configured spawn volume.

Civilian mileage and fuel are calculated once per second on the server from bounded vehicle movement. Implausible position jumps are discarded so a client-owned physics assembly cannot inject an unbounded persistent distance. Fuel includes a small occupied-idle cost, is exposed through server-authored Model/VehicleSeat attributes for the HUD, and stops a standard `VehicleSeat` when empty. Values are marked dirty at a bounded interval and once more on despawn; team-vehicle consumption is session-only.

Transfer, resale escrow and finance agreements remain future economy work.
