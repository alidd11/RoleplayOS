# Security

The server owns money, rewards, prices, content definitions, permissions, roles, inventory and ownership. Every remote has explicit registration, payload type checks, JSON-size limits, per-player token-bucket limits, request IDs, protected execution and sanitised errors. Sensitive searches and mutations are audited without recording unnecessary answer or note text.

Community administrators are scoped actors, not trusted servers. A private community can only link a Roblox group whose verified owner matches the private-server owner. Community permissions use live multi-role group ranks, explicit roles and hierarchy checks; configuration may select only server-defined presets. Group API failures fail closed and use a short negative-cache cooldown to prevent request storms.

Transactions require positive finite integer amounts, server-defined direction/reason and unique IDs; duplicate IDs and overdrafts fail. Gamepass purchase callbacks trigger an ownership recheck. DataStore writes enforce an expiring session lease and bounded failure handling.

Furniture uses ownership, property access, finite transform, room bounds, rotation, capacity and an injectable server collision check. Vehicles accept only owned IDs and configured models, and restricted tools originate in ServerStorage. Roles, stations, uniforms and loadouts are validated as a combination.

Replay-sensitive operations must use a server-issued nonce or idempotency key; job tasks use this foundation. Add production staff permission resolution before exposing review, warrant or administrative endpoints. Security relies on validation and authority, never obscure remote names.
