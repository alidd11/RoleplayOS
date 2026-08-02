# MDT and dispatch

Dispatch is strictly scoped to the current `game.JobId`. Calls, units, assignments, automatic alarms, and notifications never cross into another live server.

The MDT is available only while the player is on an authorised whitelisted duty. Every query is sanitised, length-limited, rate-limited, permission-checked by department and paginated. Person results include identity, licences and relevant flags; vehicle results include registration and ownership. Bank, home storage, furniture and unrelated private data are excluded. Every sensitive search is audited.

Dispatch control is additionally protected by a physical console. Tag a `Seat` or `VehicleSeat` with `RoleplayOSDispatchSeat`. The server verifies the player's live `Humanoid.SeatPart`, active duty and dispatcher department before it permits call creation, unit attachment or closure. The client opening a screen never grants authority.

Control-room users receive a live call queue and active-unit board. The New Control Call composer lets a dispatcher choose an incident type and priority, enter summary, location, caller, callback number and notes, then target one or more departments. All free text is filtered on the server before the call is created. Selecting a call and then a unit attaches the unit and changes its status to `Assigned`; dispatchers can also mark it `OnScene` or resolve it. A resolved call releases its units. The full snapshot is returned only by an authorised, rate-limited request; dispatch hints are no longer broadcast to unauthorised clients.

Incidents and warrants have stable IDs and audit trails. Active units and calls are temporary in-memory state and local updates use RemoteEvents.

For an automatic alarm, tag a server-owned part or model `RoleplayOSEmergencyTrigger`, add a `ProximityPrompt`, and set `IncidentType` to `BankRobbery`, `ATMRobbery`, `FireAlarm`, or `MedicalPanic`. Optional attributes are `Summary`, `Location`, `Departments` (comma-separated), and `CooldownSeconds`. The server verifies the tag, workspace ancestry, incident allowlist, player distance, per-player cooldown, and per-trigger cooldown before creating a call.
