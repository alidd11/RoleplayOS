# MDT and dispatch

The MDT is available only while the player is on an authorised whitelisted duty. Every query is sanitised, length-limited, rate-limited, permission-checked by department and paginated. Person results include identity, licences and relevant flags; vehicle results include registration and ownership. Bank, home storage, furniture and unrelated private data are excluded. Every sensitive search is audited.

Dispatch control is additionally protected by a physical console. Tag a `Seat` or `VehicleSeat` with `RoleplayOSDispatchSeat`. The server verifies the player's live `Humanoid.SeatPart`, active duty and dispatcher department before it permits call creation, unit attachment or closure. The client opening a screen never grants authority.

Control-room users receive a live call queue and active-unit board. Selecting a call and then a unit attaches the unit, changes its status to `Assigned` and publishes a small revision hint. A closed call releases its units. The full snapshot is returned only by an authorised, rate-limited request; dispatch hints are no longer broadcast to unauthorised clients.

Incidents and warrants have stable IDs and audit trails. Active units and calls are temporary state. Local updates use RemoteEvents; cross-server hints use small MessagingService events and fail gracefully. Production persistence should convert closed calls into DataStore-backed incidents through DataService and use MemoryStore sorted maps for expiring active snapshots, without polling.
