# Production hardening checkpoint

The repository-wide review is **in progress**, not complete. This checkpoint
records evidence and gaps; it is not production acceptance or permission to
publish. Refresh live main, open PRs and exact-SHA checks before continuing.

Code checkpoint: `8f2b649af0f7898adea409a86098df883405c1ed`, validated by
[Validate #2334](https://github.com/alidd11/RoleplayOS/actions/runs/37046269423)
on 2 October 2026. All 178 contract tests passed, alongside formatting, lint,
structure validation and default, acceptance and real-baseplate builds. The
deliberate-failure probe also confirmed that a failing test fails CI.

## Review standard

- Keep authority at the owning service and validate complete operations before
  changing persisted or shared state.
- Preserve unreadable stored data for recovery; do not silently replace it with
  empty ownership, zero XP or invented defaults.
- Bound retries, deadlines, histories and worker admission, including failure,
  cancellation refusal and late completion.
- Prefer small, readable changes and existing helpers to speculative abstractions,
  duplicated policy or unrelated rewrites. Update the contract documentation.
- Test actual implementations with explicit boundary doubles. Include valid paths,
  refusal invariants and combined edge cases, not only isolated happy paths.
- Review the complete diff, require exact-head CI, and verify resulting main.

Strict annotations, parsing, lint and builds do not establish a full Roblox-aware
type check or engine correctness. A higher test count does not establish that
every service, caller or interaction has been reviewed.

## Repeatable coverage and limits

| Area | Implementation exercised | Still not established by these tests |
| --- | --- | --- |
| Persistence | DataService ownership, callback replay, quarantine, dirty revisions, save/final-release faults, bounded retries and shared-record operations | Real request budgets, published contention, crashes and engine shutdown |
| Economy | EconomyService two-profile settlement, ambiguous fixture writes, recovery and receipt retention | Every financial caller, real concurrent servers and purchase acceptance |
| Startup | ServiceRegistry required/optional failure and destruction contracts | Full server boot with production assets and integrations |
| Gateway and filtering | NetworkServer callbacks, sanitisation, admission, timeout/teardown; TextFilter extraction/refusal, batches and cancellation accounting | Roblox transport/encoder compatibility, actual moderation and underlying RPC cancellation |
| Inventory and XP | InventoryService ownership/shape/quantity/stack guards; NeedsService starter grant; ProgressionService preservation, grants, replay/history and HUD DTOs | Native food tools, respawn wiring, published saves and rendered client HUD |
| Access | GroupService, AccessService, RoleService and entry verification with explicit rank/player fixtures | Real entitlements, prefetch/player signals and full role/spawn transitions |
| Dispatch | CallService patches, assignment retries, closure, release, recovery caps and notes; registered update schema | Actual UnitService/IncidentService integration, moderation and multi-client board behaviour |
| MDT projections and reads | IncidentService delayed/legacy closure protection combined with malformed-row cleanup, cap ordering and bounded history refill; RecordIndexService bucket cleanup, registration retention and bounded search refill; WarrantService malformed-state guards | Real persistence conflicts, full permission/cache/service integration and published offline searches |
| Configuration | Current defaults and persistence/progression safety bounds | Complete safety validation of every other configuration section |

See [TESTING.md](TESTING.md) for fixture details. Existing helper tests cover
additional policies; they are not full-service integration acceptance. The MDT
regressions listed above are permanent fixtures in `tests/run.luau`, executed by
CI against actual service methods. Storage and other dependencies are injected;
some cache, permission and repair methods are explicitly overridden. Earlier
manual checks supplemented these tests, rather than being their only execution.

## Remaining code work

1. Continue the remaining numeric configuration safety review, including network,
   economy, audit and performance bounds. Reproduce each gap before changing it.
2. Deepen MDT fixtures for actual record-repair replay and cache/permission/service
   interactions. Do not duplicate the existing stale-projection/maintenance,
   bucket/registration cleanup and bounded search/history refill regressions.
3. Review financial callers and lifecycle integration: cash drops, payroll,
   vehicle/vendor/property operations and refund paths. MoneyDropService,
   PayrollService and AuditService have been inspected, but inspection alone is
   not their complete failure-injection coverage.
4. Continue character/spawn/duty, custody/combat/health, vehicle/world/property,
   phone/radio/gang and client-controller/UI review. Some helper coverage exists;
   these workflows have not all received a complete repository-wide audit.
5. Recheck monetisation and asset/configuration decisions with the owner before
   release; historical pass prices, availability or ownership are not current proof.

Fix only verified defects. Do not turn unfinished adapters or roadmap features
into new features under the heading of hardening.

## External acceptance

Earlier successful Studio/live use is useful baseline evidence. Later changes
need targeted regressions against that baseline, not an assumption of either
breakage or continued correctness.

Real DataStore throttling/recovery, ambiguous writes, offline searches and
concurrent published servers (including shutdown/crash behaviour) remain **not
run** for the eventual release candidate. Full production boot, assets, native
tools/physics, multi-client workflows and device UI also require engine evidence.

Use a separate private test experience for initial persistent acceptance;
concurrent test servers must share that experience. Record exact Git SHA,
experience/place identifiers, place version, configuration and assets. Rebuild
the older staging pack from the eventual accepted main before using it. Studio
mock hooks and fixture results do not establish real DataStore acceptance.

Follow [RELEASE_READINESS.md](RELEASE_READINESS.md) and
[STAGING_ACCEPTANCE.md](STAGING_ACCEPTANCE.md). No production publish is approved
by this checkpoint. No reminder or background monitoring has been scheduled.
