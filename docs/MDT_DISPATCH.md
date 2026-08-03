# MDT and dispatch

Dispatch is strictly scoped to the current `game.JobId`. Calls, units, assignments, automatic alarms, and notifications never cross into another live server.

The MDT is available only while the player is on an authorised whitelisted duty. Every query is sanitised, length-limited, rate-limited, permission-checked by department and paginated. Person results include identity, licences and relevant flags; vehicle results include registration and ownership. Bank, home storage, furniture and unrelated private data are excluded. Every sensitive search is audited.

Dispatch control is additionally protected by a physical console. Tag a `Seat` or `VehicleSeat` with `RoleplayOSDispatchSeat`. The server verifies the player's live `Humanoid.SeatPart`, active duty and dispatcher department before it permits call creation, unit attachment or closure. The client opening a screen never grants authority.

Control-room users receive a live call queue and active-unit board. The New Control Call composer lets a dispatcher choose an incident type and priority, enter summary, location, caller, callback number and notes, then target one or more departments. All free text is filtered on the server before the call is created. Selecting a call and then a unit attaches the unit and changes its status to `Assigned`; dispatchers can also mark it `OnScene` or resolve it. A resolved call releases its units. The full snapshot is returned only by an authorised, rate-limited request; dispatch hints are no longer broadcast to unauthorised clients.

Incidents and warrants have stable IDs, durable records and audit trails. Active units and calls remain temporary, server-local state and local updates use RemoteEvents. Resolving a dispatch call asynchronously writes an idempotent closed incident projection to the persistent MDT record/index stores; this makes historical review available without leaking the active call queue into another `game.JobId`.

The MDT includes People, Vehicles and Incidents views. Authorised police duties can issue a filtered, expiry-bounded warrant from a person record and revoke it through a two-step confirmation. Active warrants appear as `WANTED` on both the person and their registered vehicle. See [MDT persistence](MDT_PERSISTENCE.md) for index and failure behaviour.

For an automatic alarm, tag a server-owned part or model `RoleplayOSEmergencyTrigger`, add a `ProximityPrompt`, and set `IncidentType` to `BankRobbery`, `ATMRobbery`, `FireAlarm`, or `MedicalPanic`. Optional attributes are `Summary`, `Location`, `Departments` (comma-separated), and `CooldownSeconds`. The server verifies the tag, workspace ancestry, incident allowlist, player distance, per-player cooldown, and per-trigger cooldown before creating a call.

## Terminal layout

The terminal is presented as a landscape tablet: an outer chassis carrying the bezel, status bar and home indicator, and an inner screen holding the pages. It opens on a home screen of cards that say what each page is for, rather than onto a search behind unlabelled tabs, and a single home control returns there once a page is open.

## The map

The map draws the same tagged geometry as the minimap, at selectable zoom. Control needs the whole picture, but a region-sized world drawn whole leaves every road a few thousandths of the surface wide and every label over its neighbour, so the region view omits point labels and the closer levels follow the officer carrying the terminal at a constant scale.

Incidents are drawn in UK response grades and units by their dispatch status. Counts name the current level and say how many of the reported incidents and units are visible at it, so a quiet map can be told apart from one zoomed past what is being looked for.

Positions are decided by the server and never by the client. Fixed world features report their own position, on-duty units report theirs, and a 999 caller reports their own as the substance of the call. A wanted person is never plotted, and a wanted vehicle is not tracked: an ANPR hit is recorded at the camera that saw it, and stays there as the vehicle drives on.
