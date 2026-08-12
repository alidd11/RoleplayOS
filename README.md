# RoleplayOS

RoleplayOS is a server-authoritative, configuration-first Roblox roleplay framework written in strict Luau and managed with Rojo. Version 0.1 establishes safe service, persistence, access, economy, ownership, MDT and dispatch boundaries for development on an empty baseplate.

The framework supports two isolated deployments: the public game and the official group-whitelisted game. Player data is namespaced so progress does not cross between them.

## Quick start

1. Install [Aftman](https://github.com/LPGhatguy/aftman), then run `aftman install`.
2. Run `rojo serve` and connect the Rojo Studio plugin.
3. Add Teams and map assets whose names match configuration; all production asset IDs remain unset.
4. Run `stylua --check src tests`, `selene src tests`, `bash scripts/validate-structure.sh`, and `rojo build --output build/RoleplayOS.rbxlx`.

Core gameplay decisions are made on the server. Clients request actions and receive sanitised response envelopes; they never supply authoritative prices, rewards, permissions, balances, ownership, role grants, or model IDs.

## Studio content quick reference

Place the clean master copy of every vehicle or Tool under `ServerStorage/RoleplayOSAssets`. The framework clones those templates when needed; do not place runnable scripts, remotes, prompts or click detectors inside them.

```text
RoleplayOSAssets
├── README                         Studio-facing placement guide
├── Vehicles
│   ├── Civilian
│   │   ├── Starter                starter vehicles
│   │   ├── Standard               normal dealership vehicles
│   │   └── Premium                gamepass-restricted vehicles
│   └── Services/<Department>      team/rank and issued public-job fleets
└── Tools
    ├── Civilian
    ├── Shared
    └── Services/<Department>      team/rank tools
```

The police warrant-card presentation model lives at
`Tools/Services/Police/Shared/Warrant Card`. `IdentificationService` clones it only
for an active Police duty and fills the officer's character name, rank, warrant
number, force and avatar portrait on the server. Keep this template script-free.

To price a new civilian vehicle, select its top-level `Model` in Studio and add a **Number** attribute named `Price`, such as `25000`. `Standard` and `Premium` vehicles require a non-negative price; a `Starter` vehicle may be free. Optional attributes include `DisplayName`, `DefaultColour`, `DealershipId`, `GamepassId`, and `RoleplayOSAssetId`. Prices are read and charged only by the server; a client cannot submit or change the amount.

Vehicles already declared in `src/shared/Config/Config.luau` use the price in that declaration. The config entry is deliberately authoritative, so do not also try to override its price with a Model attribute. See the complete [vehicle and Tool content guide](docs/CONTENT_AUTHORING.md).

See [Architecture](docs/ARCHITECTURE.md), [Access control](docs/ACCESS_CONTROL.md), [Roblox groups](docs/ROBLOX_GROUPS.md), [Interface system](docs/UI_SYSTEM.md), [UX benchmark](docs/UX_BENCHMARK.md), [Advanced settings](docs/SETTINGS.md), [Progression](docs/PROGRESSION.md), [Spawning](docs/SPAWNING.md), [Vehicles](docs/VEHICLES.md), [Uniform changing rooms](docs/UNIFORMS.md), [Minimap](docs/MINIMAP.md), [Street and district names](docs/LOCATIONS.md), [MDT persistence](docs/MDT_PERSISTENCE.md), [Development](docs/DEVELOPMENT.md), [Testing](docs/TESTING.md), [Roblox runtime guidance](docs/ROBLOX_RUNTIME_GUIDANCE.md), and the [Roadmap](docs/ROADMAP.md). This is an engineering foundation with a functional premium start experience, not a production-ready game.

Before preparing a publish, follow the concise [release-readiness gate](docs/RELEASE_READINESS.md).

To connect RoleplayOS to an existing map, follow [Real baseplate deployment](docs/REAL_BASEPLATE_DEPLOYMENT.md). Its migration-specific Rojo project preserves the map and unrelated Studio content.

Content builders should follow [Vehicle and Tool content authoring](docs/CONTENT_AUTHORING.md) and the [UK environment modelling bible](docs/UK_ENVIRONMENT_MODELLING_BIBLE.md).

The optional free player-to-player voice route is documented in [In-game phone voice](docs/VOICE_PHONE.md).

## Repository layout

- `src/shared/Config/EDIT_HERE`: the only routine configuration files; numbered so they remain easy to find in Studio Explorer
- `src/shared/Utility`: replicated validation and pure logic; never put server secrets or mutable state here
- `src/server/Services`: authoritative gameplay domains, one clearly named service per file
- `src/server/Systems`: framework infrastructure such as networking and service lifecycle
- `src/client/Controllers`: input, HUD and feature controllers
- `src/client/UI`: reusable visual modules shared by controllers
- `server-assets`: canonical, server-only vehicle, Tool and interior templates
- `scripts`: validation and one-time Studio installation utilities
- `tests`: pure module and runtime acceptance tests
- `docs`: architecture, authoring and subsystem contracts

For the complete folder map and naming rules, see [Project structure](docs/PROJECT_STRUCTURE.md).

Licensed under MIT.
