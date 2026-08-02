# Performance

Profiles load once and save only when dirty, on a timed batch, leave or shutdown. Static configuration is frozen and cached. The join catalogue sends summaries rather than full profiles or full vehicle/property/furniture catalogues. MDT results paginate and remote payloads are capped.

Runtime state uses events rather than DataStore or MemoryStore polling. Dispatch messages contain only kind, stable ID and revision. Property interiors clone on demand and unload after the last occupant and a safety delay. Server-only definitions and templates do not replicate.

Team spawn pads use Roblox's native `TeamColor` and `RespawnLocation` behaviour. RoleplayOS indexes their `SpawnId` attributes once at startup; it performs no per-frame spawn scanning or position polling.

Dispatch seats and minimap geometry use `CollectionService` added/removed signals. Dispatch state is pushed as small revision hints and fetched only when an authorised interface is open. Phone calls are in-memory signalling records; text history is bounded to the configured per-character limit. None of these systems introduces a frame loop or server polling loop.

Logger metadata is the initial instrumentation hook. Measure service startup, persistence latency, remote rejection counts, catalogue sizes and live instance counts before tuning. Debounce high-frequency state and batch durable updates.
