# Roblox runtime guidance

This note records the official Roblox guidance used for RoleplayOS runtime decisions. It is an engineering baseline, not a claim that performance has been proven on production hardware. Profile representative public and whitelisted servers before raising player or content limits.

## Performance and streaming

Roblox recommends avoiding expensive work on frame-based events unless the frequency is essential, throttling remote traffic, sending only the data that changed, and spreading expensive work across frames. RoleplayOS therefore uses bounded periodic loops and delta-driven needs updates rather than per-frame replication.

- [Improve performance](https://create.roblox.com/docs/performance-optimization/improve)
- [Identify performance issues](https://create.roblox.com/docs/performance-optimization/identify)

`Workspace.StreamingEnabled` is a Studio property and cannot be enabled by a runtime script. New large maps should enable it in Studio and test streaming boundaries on low-memory mobile devices. Gameplay code must tolerate Workspace descendants streaming out on clients; authoritative server systems must not depend on a client proving that a distant instance exists.

- [Instance streaming](https://create.roblox.com/docs/workspace/streaming)

## Physics and touch security

Roblox documents that a client with network ownership can manipulate an unanchored assembly and can influence `Touched` behaviour. A touch is therefore only a candidate signal. RoleplayOS must corroborate security-sensitive touches with server-owned identity, configured tags, plausible position or speed, cooldowns, and authoritative records. Vehicle ownership should be explicitly assigned to the driver for responsiveness, while important validation remains on the server.

- [Network ownership](https://create.roblox.com/docs/physics/network-ownership)
- [Network ownership, movement validation, and physics security](https://create.roblox.com/docs/scripting/security/network-ownership)

Road-safety sensors now register and unregister dynamically and periodically remove expired cooldown and unfinished average-speed journey state. This bounds memory growth during long-running servers and supports dynamically constructed map content on the server. Fixed cameras use RoleplayOS's bounded server telemetry rather than trusting the assembly's instantaneous client-replicated velocity; implausible movement invalidates the sample instead of issuing a fine.

## Durable and ephemeral data

Roblox DataStore entries are shared by all servers in an experience and durable between sessions. `UpdateAsync()` is the appropriate primitive where multiple servers may update a key, but calls can fail and consume both read and write budgets. Unknown write outcomes require idempotent operations and, where consequential, an uncached verification read.

- [Data stores](https://create.roblox.com/docs/cloud-services/data-stores)
- [Data store limits and errors](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits)
- [Data store caching and versioning](https://create.roblox.com/docs/cloud-services/data-stores/versioning-listing-and-caching)

MemoryStore is shared across live servers but is ephemeral and TTL-based. It is suitable for short-lived presence, session leases, and transient indexes, not custody, vehicle, warrant, or financial records. MessagingService is best-effort cross-server signalling and must not be used as the source of truth. RoleplayOS dispatch calls intentionally remain specific to one server; adding MessagingService to that path would violate the product requirement unless a future feature is explicitly global.

- [Memory stores](https://create.roblox.com/docs/cloud-services/memory-stores)
- [Cross-server messaging](https://create.roblox.com/docs/cloud-services/cross-server-messaging)

Persistent person, vehicle, custody and warrant lookup still needs a durable index design. Do not use `ListKeysAsync()` for interactive MDT search. Maintain bounded, normalised secondary index entries during the same logical server transaction, include revision and idempotency identifiers, and provide repair tooling for partial failures.

## Phone voice capability

Roblox modular audio can route voice-eligible `AudioDeviceInput` streams using access lists and audio objects. Voice is not universally available: eligibility, experience settings, account verification, region, microphone permission and runtime object readiness all matter. A free same-server call can therefore be built without a paid third-party audio service, but the server must capability-check both participants and fail closed. Text and call signalling must continue to work when voice is unavailable.

- [Add voice chat](https://create.roblox.com/docs/tutorials/use-case-tutorials/audio/add-voice-chat)
- [Audio objects](https://create.roblox.com/docs/audio/objects)
- [AudioDeviceInput](https://create.roblox.com/docs/reference/engine/classes/AudioDeviceInput)

Cross-server voice calls are not implied by MessagingService. MessagingService can signal an invitation, but it does not carry a live microphone stream. RoleplayOS should keep player calls same-server unless Roblox provides and the project validates an explicit supported cross-server audio architecture.

## Verification targets

- Profile server heartbeat and script cost with Developer Console and MicroProfiler at intended player capacity.
- Record remote events per second before and after enabling needs, MDT and dispatch systems.
- Test StreamingEnabled on minimum-spec mobile clients while spawning vehicles and switching CCTV views.
- Test road-safety sensors with client-owned vehicles, deliberately duplicated touches and dynamically added or removed sensors.
- Test DataStore throttling, ambiguous write failure, concurrent joins and shutdown deadlines in a separate published test universe.
- Test phone calls with eligible voice users, ineligible users, denied microphone permission, player departure and server shutdown.
