# Engineering instructions

Use British English in documentation and player-facing text. Use `--!strict` where Roblox APIs permit it. Keep modules small, typed, and configuration-first.

## Dependency rules

- `shared` modules must not depend on client or server modules.
- Client controllers may depend only on replicated shared modules, remotes, and other controllers through the client context.
- Services receive dependencies through `context.Services`; never require another service module directly.
- Register services explicitly in `init.server.luau` in dependency order. Circular dependencies are forbidden.
- `Init` stores dependencies and registers infrastructure; `Start` connects events and begins work; `Destroy` releases connections/state.
- A required service failure aborts startup. Mark only genuinely degradable integrations `Optional = true`.

## Authority boundaries

- Only `DataService` accesses persistent DataStores.
- Only `EconomyService` changes balances.
- Only role, spawn, uniform and loadout services assign their corresponding runtime state.
- Never trust client prices, rewards, ownership, access, model IDs, placements, task completion, or purchase success.
- Register all remotes centrally through `NetworkServer`, with a schema, rate limit and sanitised envelope.
- Persistent records use stable string IDs and serialised primitives, never Instances, Enums, CFrames or Vector3s.

Before committing, run formatting, Selene, structure validation, tests where a Roblox test runtime is available, and a Rojo build. Update subsystem documentation when a contract changes. Never commit secrets or production asset IDs.
