# Spawning

Every RoleplayOS spawn is a native `SpawnLocation` bound to a configured Team through `TeamColor`. Apply the `RoleplayOSSpawnPad` tag to each pad: startup then asks for the tagged set directly instead of walking every descendant of the workspace, which is unremarkable on a baseplate and blocks startup on a region-sized map. Untagged maps still work, through that walk, and say so in the log. Pads are named after their team (`Civilian`, `Police`, `Ambulance` or `Fire`). A stable `SpawnId` attribute distinguishes multiple pads for the same team and binds each one to a station and explicit permitted roles and departments. Duplicate, absent or mismatched IDs are unavailable.

Duty start preflights the complete profile, role, department, station and spawn combination before changing runtime state. The server re-evaluates role access, assigns the configured Team, sets `RespawnLocation` to the exact pad, and calls `LoadCharacter`. Roblox performs the native spawn. RoleplayOS then applies the uniform and clones only the ServerStorage loadout. The active duty record is created last. Failure rolls back team assignment and does not register an active unit.

The registry scans the Workspace once during service startup. There is no frame loop, polling or repeated map search. Native Roblox spawning handles simultaneous arrivals. Production maps should provide clear space above every pad and keep `AllowTeamChangeOnTouch` disabled.

Development pad attributes:

- `Civilian` with `SpawnId = "CityCivilian"`
- `Police` with `SpawnId = "PoliceLockerRoom"`
- `Police` with `SpawnId = "PoliceVehicleBay"`
- `Ambulance` with `SpawnId = "AmbulanceLockerRoom"`
- `Fire` with `SpawnId = "FireLockerRoom"`

Changing a `SpawnId` requires the matching configuration change and a Rojo build. Never accept a world position, team, station or spawn identifier chosen without server validation.
