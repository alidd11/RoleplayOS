# Vehicles

Dealership catalogues refer to configured vehicle IDs. Purchase revalidates catalogue membership and access, debits the configured price, then creates a GUID ownership record and generated registration. Ownership, colour, mileage, fuel, condition, insurance, tax and garage are persisted per character.

Spawning checks active character ownership, terminal distance, spawn-point clearance, cooldown and the one-active-vehicle limit before cloning a configured ServerStorage model. Clearance checks recognise existing RoleplayOS vehicles and characters in the configured spawn volume.

Civilian mileage and fuel are calculated once per second on the server from bounded vehicle movement. Implausible position jumps are discarded so a client-owned physics assembly cannot inject an unbounded persistent distance. Fuel includes a small occupied-idle cost, is exposed through server-authored Model/VehicleSeat attributes for the HUD, and stops a standard `VehicleSeat` when empty. Values are marked dirty at a bounded interval and once more on despawn; team-vehicle consumption is session-only.

Transfer, resale escrow and finance agreements remain future economy work.


## Taking over the chassis interface

Vehicles are driven by a third-party chassis, which brings its own gauges. RoleplayOS presents the readouts itself instead, so they match the rest of the interface, scale with the device and respect the safe area, none of which a chassis interface does.

The chassis clones its gauges into `PlayerGui` when a player takes a seat. Those are disabled on sight by name, listed in `Config.Chassis.SuppressGuiNames`. They are disabled rather than destroyed: the chassis may still be driving them, and removing something another system owns produces errors that are hard to trace back here. Names differ between A-Chassis forks, so check what actually appears in `PlayerGui` while seated and add it to that list rather than assuming the shipped list is complete.

Gear and engine speed are read from the chassis's own values folder, searched under the seat and then the vehicle model, since forks disagree on where it sits. Where no chassis is present the gear falls back to throttle direction, which can only distinguish forward, reverse and neutral.

Road speed is measured from the seat's own velocity rather than read from the chassis, so it is correct whatever chassis a vehicle uses, or none.

Fuel is not read from the chassis. RoleplayOS owns fuel on the server and publishes it as an attribute; a client-side value could not be trusted in any case.

Emergency lighting and siren systems are left alone. They are part of the vehicle and are presented in the world rather than on screen, so they do not compete with the interface for space.
