# Security

The server owns money, rewards, prices, content definitions, permissions, roles, inventory and ownership. Every remote has explicit registration, payload type checks, byte limits, per-endpoint and global per-player token buckets, concurrency caps, request IDs, protected execution and sanitised errors. Payloads are rejected for excessive nesting, nodes or strings, non-finite numbers, unsupported Roblox instances, and cycles. RemoteFunction responses are rebuilt from the declared envelope fields, and response Data is independently bounded for depth, nodes and string volume; unsupported Roblox objects, cycles and non-finite values are refused before they reach the client. Vector3 remains an explicit fixed-size response value because live taxi navigation uses it as a waypoint. Sensitive searches and mutations are audited without recording unnecessary answer or note text.

Token buckets survive quick reconnects and are pruned after their idle TTL. Active
request tracking is published only for accepted handlers, not busy/shutdown
refusals. Timed-out handlers remain counted until completion or the configured
abandonment ceiling; completion and teardown release each slot at most once.

Text filtering has a four-second caller deadline and a shared cap of 16 worker
coroutines. Timed-out workers release capacity only after confirmed cancellation
or completion. Cancellation refusal therefore fails closed rather than admitting
unbounded replacement workers during a stalled moderation call. Filter or
extraction failure never permits the raw input to be displayed in live servers.

Audit persistence uses a bounded pending ring and a single controlled flush path. Low-volume events flush on a short interval, bursts request one immediate flush, failed writes are retried without allowing the queue or task count to grow without bound, and shutdown drains only within its configured deadline. If a prolonged persistence outage fills the buffer, the oldest pending audit entries are dropped and the server logs the loss rather than sacrificing live-server stability.

Startup validation rejects present non-finite, fractional or undersized audit
buffer counts, and non-finite or non-positive flush timings. Omitted settings keep
the existing service fallbacks. The pending minimum remains 25; burst thresholds
above capacity and positive sub-second timings retain the existing runtime clamps.
No shipped audit defaults are changed by these guards.

Emergency alarms, flashlight state, stamina, walk speed, hunger, food prices, economy debits, dispatch chair access, team duty, and MDT permissions are server-authoritative. Security-sensitive robbery systems should call `EmergencyTriggerService:Trigger()` from server code or use a tagged server-owned prompt; clients never select incident priority or food price.

The official whitelisted deployment uses configured Roblox group links and fails closed when membership cannot be verified. Group API failures use a short negative-cache cooldown to prevent request storms.

Transactions require positive finite integer amounts, server-defined direction/reason and unique IDs; duplicate IDs and overdrafts fail. Gamepass purchase callbacks trigger an ownership recheck. DataStore writes enforce an expiring session lease and bounded failure handling.

Furniture uses ownership, property access, finite transform, room bounds, rotation, capacity and an injectable server collision check. Vehicles accept only owned IDs and configured models, and restricted tools originate in ServerStorage. Roles, stations, uniforms and loadouts are validated as a combination.

Replay-sensitive operations must use a server-issued nonce or idempotency key; job tasks use this foundation. Add production staff permission resolution before exposing review, warrant or administrative endpoints. Security relies on validation and authority, never obscure remote names.
