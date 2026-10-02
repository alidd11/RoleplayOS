# Testing

`tests/run.luau` covers access, token buckets, transaction safety, character validation, configuration, registrations, property rules, furniture bounds, serialisation, migration and response envelopes. It is Roblox-runtime compatible and can be mapped into a dedicated Rojo test place or migrated directly into TestEZ once the package manager is introduced.

For the staging build, runtime wiring checks and full multi-client/live-server release gates, follow [STAGING_ACCEPTANCE.md](STAGING_ACCEPTANCE.md). The separate `acceptance.project.json` maps the test scripts; `default.project.json` deliberately does not.

## Automated contract tests

Run `aftman install`, then `lune run scripts/run-tests.luau` from the repository root. CI executes the entire `tests/run.luau` suite, alongside formatting, Selene, structure validation and default, acceptance and real-baseplate Rojo builds. Builds establish packaging, not runtime acceptance. Lune is pinned in `aftman.toml`. CI also injects an intentional test failure and checks that the runner exits unsuccessfully.

The headless adapter loads repository module source unchanged, with a mounted `script.Parent` tree and isolated module cache. Lune supplies native Roblox datatypes and Instances plus its task scheduler. Test doubles provide unique deterministic GUIDs, an empty player registry, Studio mode and a deterministic seeded random generator. DateTime delegates calendar validation to Lune. Unsupported services and methods throw; DataStore, MemoryStore, teleport and text-filter RPCs are not simulated as successful calls. Service tests explicitly inject their own bounded fixtures through the usual dependency interfaces.

This is contract regression coverage, not Roblox engine, physics, networking or published-place acceptance. Production filtering is not exercised by the Studio-mode double. Continue running the same specs in Studio; use targeted regressions against the previously working Studio/live baseline after changes. Real DataStore throttling, ambiguous writes, simultaneous joins, shutdown and concurrent published-server behaviour remain external release gates. Use a separate private test experience for initial persistence acceptance.

`scripts/persistence-tests.luau` adds headless failure-injection contracts against the actual DataService and its attached modules. Each case uses an isolated runtime, explicit player double and detached atomic-store fixture with callback replay and before/after-commit fault hooks. It covers load ownership/idempotence, quarantine backup failure, late departure, dirty revisions, final-save barriers, ambiguous release/reacquisition, shutdown deadlines, retry caps, shared tombstones, mock reference isolation, registration swaps and shoulder-holder verification. Budget waits are explicitly bypassed in these fixtures: they do not prove real throttling, cross-process contention or crash recovery.

`scripts/economy-tests.luau` exercises the actual EconomyService with detached shared-record/profile fixtures: account isolation, replay after reconstructed runtime state, bounded transaction/receipt histories, two-profile settlement, changed-operation refusal, pre/post-commit save faults, ambiguous journal/acknowledgement results, and departure during reservation. A simulated restart reconstructs the service from fixture-durable profiles; it is not a real crash or concurrent published-server test. Real player signals, request budgets and service startup are not simulated by this suite.

`scripts/network-tests.luau` invokes callbacks registered by the actual NetworkServer: authorisation, payload/encoding/schema failures, rate limits, envelope sanitisation, shutdown races, concurrency, timeouts, abandonment and teardown. Lune's property adapter holds RemoteFunction callbacks, and an explicit JSON adapter supplies encoding. These are direct server callback tests, not Roblox client/server transport or encoder compatibility tests. Handler fixtures exit within bounded deadlines. Busy/shutdown refusals must not retain empty user tracking; accepted work remains counted until completion or abandonment.

`scripts/inventory-tests.luau` exercises the actual InventoryService's ownership,
quantity, stack and legacy-shape contracts, including preservation of unreadable
data. It also calls actual NeedsService starter-food logic with a presentation
double, proving inventory grant idempotence without claiming native Tool
activation, respawn wiring or hunger persistence acceptance.

`scripts/access-tests.luau` exercises actual group lookup, access, role assignment
and entry verification with explicit rank/player fixtures. It covers cache expiry,
negative-cache recovery, missing/non-member groups, profile/player fences, stalled
RPC deadlines, shared admission, cancellation refusal and teardown. The fixture
overrides only its isolated task adapter for cancellation failure. Player signals,
prefetch pacing, real group ranks and Roblox RPC cancellation remain Studio/live
acceptance work; no mock result establishes a production entitlement.

`scripts/call-tests.luau` exercises actual CallService updates, assignment retries,
terminal resolution, last-unit release, recovery caps and operational-note
retention. It also invokes the registered dispatch-update schema directly. Units,
publication, incident scheduling and audit are explicit dependency doubles; note
filtering follows the headless Studio bypass. These tests do not establish actual
UnitService wiring, filtered RPCs, incident persistence or multi-client acceptance.

`scripts/text-filter-tests.luau` exercises the actual TextFilter module with explicit
non-Studio filter/extractor fixtures: broadcast and recipient selection, refusal
and recovery, parallel batches, caller deadlines, cancellation and cancellation
refusal. An isolated task adapter injects cancellation failure. This verifies
worker admission and fail-closed contracts, not Roblox moderation output or the
engine's ability to cancel an underlying web request.

`scripts/progression-tests.luau` exercises actual ProfileSchema migration and
ProgressionService reads/grants with unreadable XP, mutation containers, tracks,
sparse retention lists and partial legacy state. Valid rewards retain bounded
history and replay IDs. Data access, audit and HUD transport are explicit doubles;
published saves and real client rendering remain acceptance work.

`scripts/config-tests.luau` exercises actual ConfigValidator persistence timing,
retry-count and optional wait/size bounds, including non-finite values. Positive
defaults, optional absence and lease/size relationships remain covered. These
tests reject unsafe inputs; they do not run an infinite retry or wait in CI. Audit
buffer counts and flush timings also cover refusal, optional absence and clamps.

`scripts/audit-tests.luau` exercises actual AuditService ring retention, dropped
entry counts, chronological batch extraction, failed-flush restoration and
duplicate-ID suppression. DataService and logging are explicit dependency doubles;
periodic scheduling, engine shutdown and real DataStore writes are not exercised.
