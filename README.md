# RoleplayOS

RoleplayOS is a server-authoritative, configuration-first Roblox roleplay framework written in strict Luau and managed with Rojo. Version 0.1 establishes safe service, persistence, access, economy, ownership, MDT and dispatch boundaries for development on an empty baseplate.

The same framework supports the public game and privately operated roleplay communities. Community owners can manage membership, staff hierarchy, sessions, policies and branding within server-enforced limits; see [Private communities](docs/COMMUNITIES.md).

## Quick start

1. Install [Aftman](https://github.com/LPGhatguy/aftman), then run `aftman install`.
2. Run `rojo serve` and connect the Rojo Studio plugin.
3. Add Teams and map assets whose names match configuration; all production asset IDs remain unset.
4. Run `stylua --check src tests`, `selene src tests`, `bash scripts/validate-structure.sh`, and `rojo build --output build/RoleplayOS.rbxlx`.

Core gameplay decisions are made on the server. Clients request actions and receive sanitised response envelopes; they never supply authoritative prices, rewards, permissions, balances, ownership, role grants, or model IDs.

See [Architecture](docs/ARCHITECTURE.md), [Access control](docs/ACCESS_CONTROL.md), [Roblox groups](docs/ROBLOX_GROUPS.md), [Interface system](docs/UI_SYSTEM.md), [Spawning](docs/SPAWNING.md), [Development](docs/DEVELOPMENT.md), [Testing](docs/TESTING.md), and the [Roadmap](docs/ROADMAP.md). This is an engineering foundation with a functional premium start experience, not a production-ready game.

## Repository layout

- `src/shared`: replicated types, safe configuration and pure logic
- `src/server`: bootstrap, service registry, networking and authoritative services
- `src/client`: replaceable controllers and view-model boundary
- `server-assets`: server-only tools and interior templates
- `tests`: pure module test harness/specifications
- `docs`: architecture and subsystem contracts

Licensed under MIT.
