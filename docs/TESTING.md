# Testing

`tests/run.luau` covers access, token buckets, transaction safety, character validation, configuration, registrations, property rules, furniture bounds, serialisation, migration and response envelopes. It is Roblox-runtime compatible and can be mapped into a dedicated Rojo test place or migrated directly into TestEZ once the package manager is introduced.

For the staging build, runtime wiring checks and full multi-client/live-server release gates, follow [STAGING_ACCEPTANCE.md](STAGING_ACCEPTANCE.md). The separate `acceptance.project.json` maps the test scripts; `default.project.json` deliberately does not.

## Automated contract tests

Run `aftman install`, then `lune run scripts/run-tests.luau` from the repository root. CI executes the entire `tests/run.luau` suite, alongside formatting, Selene, structure validation and a Rojo build. Lune is pinned in `aftman.toml`. CI also injects an intentional test failure and checks that the runner exits unsuccessfully.

The headless adapter loads repository module source unchanged, with a mounted `script.Parent` tree and isolated module cache. Lune supplies native Roblox datatypes and Instances plus its task scheduler. Test doubles provide unique deterministic GUIDs, an empty player registry, Studio mode and a deterministic seeded random generator. DateTime delegates calendar validation to Lune. Unsupported services and methods throw; DataStore, MemoryStore, teleport and text-filter RPCs are not simulated as successful calls. Service tests explicitly inject their own bounded fixtures through the usual dependency interfaces.

This is contract regression coverage, not Roblox engine, physics, networking or published-place acceptance. Production filtering is not exercised by the Studio-mode double. Continue running the same specs in Studio; use targeted regressions against the previously working Studio/live baseline after changes. Real DataStore throttling, ambiguous writes, simultaneous joins, shutdown and concurrent published-server behaviour remain external release gates. Use a separate private test experience for initial persistence acceptance.

`scripts/persistence-tests.luau` adds headless failure-injection contracts against the actual DataService and its attached modules. Each case uses an isolated runtime, explicit player double and detached atomic-store fixture with callback replay and before/after-commit fault hooks. It covers load ownership/idempotence, quarantine backup failure, late departure, dirty revisions, final-save barriers, ambiguous release/reacquisition, shutdown deadlines, retry caps, shared tombstones, mock reference isolation, registration swaps and shoulder-holder verification. Budget waits are explicitly bypassed in these fixtures: they do not prove real throttling, cross-process contention or crash recovery.
