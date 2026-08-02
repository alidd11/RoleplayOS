# Testing

`tests/run.luau` covers access, token buckets, transaction safety, character validation, configuration, registrations, property rules, furniture bounds, serialisation, migration and response envelopes. It is Roblox-runtime compatible and can be mapped into a dedicated Rojo test place or migrated directly into TestEZ once the package manager is introduced.

For the staging build, runtime wiring checks and full multi-client/live-server release gates, follow [STAGING_ACCEPTANCE.md](STAGING_ACCEPTANCE.md). The separate `acceptance.project.json` maps the test scripts; `default.project.json` deliberately does not.

CI always runs formatting, Selene, structure validation and a Rojo build. It intentionally does not claim to execute Roblox-runtime tests on a generic Linux runner. Before release, run the specs in Studio or a pinned Roblox-compatible test runner and add integration tests for DataStore failure, simultaneous join, marketplace failure, shutdown and cross-server dispatch.
