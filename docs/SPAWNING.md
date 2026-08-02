# Spawning

Every RoleplayOS spawn is a stable configuration ID bound to one station and an explicit set of permitted roles and departments. The corresponding map part has a unique configured name. Duplicate, absent or mismatched points are unavailable; the framework never falls back to a similarly named object elsewhere in the map.

Duty start preflights the complete profile, role, department, station and spawn combination before changing runtime state. The server re-evaluates role access, assigns the configured team, reloads the character, pivots it above the resolved point, clears assembly velocity, applies the role uniform and clones only its ServerStorage loadout. The active duty record is created last. Failure rolls back team assignment and does not register an active unit.

Spawn points may be Parts or SpawnLocations. SpawnLocations also become the player's Roblox respawn location; ordinary Parts are used only for the controlled pivot. Short reservations distribute simultaneous arrivals across safe offsets. Production maps should provide clear volumes of at least eight studs above every marker and keep markers anchored, non-collidable and invisible.

Map naming for the development configuration:

- `RPSpawn_CityCivilian`
- `RPSpawn_PoliceLockerRoom`
- `RPSpawn_PoliceVehicleBay`
- `RPSpawn_AmbulanceLockerRoom`
- `RPSpawn_FireLockerRoom`

Changing a map name requires the matching configuration change and a Rojo build. Never accept a world position, part name, station or spawn identifier chosen without server validation.
