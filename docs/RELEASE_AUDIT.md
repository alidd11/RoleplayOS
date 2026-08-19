# Production test release — audit

State of the tree at `109a210`. Every claim below was re-checked against the
working tree at the time of writing rather than carried over from an earlier
pass. This supersedes `RELEASE_AUDIT_2026-08-07.md` and `AUDIT_2026_08_18.md`,
both removed alongside this update — their live findings are folded in below
and their stale ones are corrected, so there is one current document instead
of three that can silently disagree. Verdict at the bottom.

## Blockers

### 1. Three firearm gamepasses take Robux and give nothing

| Pass | Gamepass id | Price |
| --- | --- | --- |
| `CivilianHandgun` | 1937822271 | 125 Robux |
| `CivilianShotgun` | 1934518052 | 175 Robux |
| `CivilianRifle` | 1934955986 | 225 Robux |

This is a bigger list than it used to be. Weapon claiming no longer goes
through the old `Config.EquipmentPasses` table — that table and the
`LoadoutService:ApplyEquipmentPasses` function that read it were both deleted
this cycle, since gamepass owners now have to visit a dealer like everyone
else. The dealer is `Config.Vendors.Definitions.StreetDealer`, and its `Items`
list only offers three tools: `Knife` (900 cash or `CivilianKnife`,
1937446295), `Machete` (`ZKnife`'s and Machete's own passes). Handgun, Shotgun
and Rifle appear nowhere in `Vendors`, nowhere in `Config.Tools` (the full tool
list is `Knife`, `Machete`, `ZKnife`, `Handcuffs`, `Taser`, `MedicalBag`,
`PoliceWarrantCard`, `PAVA` — no firearm of any kind), and nowhere under
`server-assets/Tools`. A player who buys any of the three receives nothing to
show for it.

**Cannot ship with these on sale.** Delisting needs the account holder;
building the tools is not a test-release-sized job. The account holder has
said they will handle this directly.

### 2. Production validator still fails four checks

Running `./scripts/validate-structure.sh` (non-production mode) currently
warns:

- `Framework.Environment` is not `"Production"`
- `UseMockDataInStudio` is not `false`
- `GrantMockEmergencyAccessInStudio` is not `false`
- one or more uniform template IDs are empty

The first three are deliberate development switches, not defects — flipping
them is a deploy-time decision for whoever publishes the build, not something
to change in the working tree ahead of time. The fourth is real: shirt and
trouser template IDs are empty for Police, Ambulance, Fire, Transport,
Highways and Prison in `EDIT_HERE/04_Uniforms.luau`. Only the base civilian
outfit has real IDs. This needs actual catalog asset IDs from the group's own
uniform assets — it isn't something that can be filled in from the code.

## Closed since the last pass

### 3. The three untracked vehicle assets are now committed

Previously flagged as present in `server-assets/Vehicles` but absent from git
(the 72' BMW 545e, 23' Toyota Corolla HB, and 24' Volvo V90). All three are
now tracked (`git ls-files` confirms it). A fresh clone builds the same place
as this one for these three files.

### 4. `NetworkService.luau` split into per-domain modules

Was a single 1,709-line file of 78 `RegisterFunction`/`RegisterEvent` calls.
Every endpoint only ever touched `self` and its own locals, so it split
cleanly with no behaviour change: it's now `NetworkService/init.luau` plus
eleven domain modules (Core, Vehicle, Duty, Character, Gang, MDT, Dispatch,
Phone, Taxi, Custody, Radio) and a shared `Validators` module, using Rojo's
`init.luau` folder convention. Verified by `rojo build`, the 78-endpoint
rate-limit coverage check, and a live Play-mode boot reaching
`Network:MarkReady()` with no errors.

### 5. `VendorController.luau` formatting

`stylua --check` was failing on two lines over the wrap width. Fixed and
clean.

### 6. `renderCareers` dead code — already removed

Confirmed gone; not re-litigated here.

## In progress

### 7. `DeveloperDashboard.luau` split

Still the largest single file at 3,665 lines before this pass started. A
split is underway: the stateless UI helper functions (`tileGrid`, `button`,
`card`, `posterTile`, etc.) have already been extracted into a sibling
widgets module. The five panel renderers (Play, Civilian Jobs, Store, Servers,
Help) are being split out next. Not yet complete or verified at the time of
this document — check `git log` on `src/client/UI/DeveloperDashboard/` for
current status before relying on this section.

## Known defects, not re-verified live this pass

### 8. Vehicles may still launch on first dismount

Reported on the Peugeot van: it rises sharply and drops back.
`VehicleSpawnerService:_place` still sets a vehicle down 0.75 studs above the
bay (unchanged since last checked), and A-Chassis still unanchors every part
at initialise, so a rigid multi-part body is still released into freefall as
a unit on the reported mechanism. That clearance is deliberate — a comment
above it records that placing an imported pivot flat on the surface put
wheels under the map and got assemblies deleted — so it should not simply be
zeroed. The underlying code path is unchanged; this has not been re-observed
live since it was first reported, and this pass did not re-test it either.

### 9. The Sur-Ron's air horn

Previously found to be a 113ms blip (asset `691472063`) against the van's
2.46s horn, baked into the vehicle model rather than referenced from `src`,
so it isn't independently checkable by reading source. Not re-verified this
pass.

## Checked and sound

- **Rate limiting.** A global bucket at 30 capacity refilling 10/s, plus
  per-request buckets. `SetEmergencyLights` is 8 capacity refilling 8/s (see
  `Config.Network.RateLimits`) against a worst case of two requests per panel
  press.
- **Remote validation and rate-limit coverage.** All 78 currently registered
  client-callable endpoints have explicit rate limits (up from 48 at the last
  full audit — 30 more endpoints have shipped since).
- **Persistence.** `DataService` uses `UpdateAsync` for shared keys and wraps
  DataStore and player calls in `pcall`.
- **ToS.** No references to controlled substances or alcohol anywhere in
  `src`.
- **Hygiene.** No `TODO`, `FIXME`, "not implemented" or "coming soon" markers
  anywhere in `src`. `stylua`, `selene` (0 errors, 0 warnings across `src` and
  `tests`) and `rojo build` are all clean as of this pass.
- **Tests.** An acceptance runner and harness exist under `tests/`.

## Not verified in play

Everything in this document was checked by reading source, running the
linters/build, or (where noted) an isolated-render UI test in Studio — never
a real two-player session. The following still need a genuine multiplayer
pass, and no amount of further static checking will resolve them:

- ELS: `OFF` killing lights and siren, `999` starting the wail, `AT SCENE`
  lighting the work lamps.
- Custody: the full cuff → seat-in-chair → book → cell → sentence → release
  chain with two real players. The chair-triggered booking terminal and the
  player list have been confirmed to render correctly via isolated-instance
  screenshots, which proves the UI builds and opens the right screen but not
  that the underlying multiplayer flow (a real ProximityPrompt trigger, a
  real second player being cuffed by someone other than themselves) works
  end-to-end.
- Gang territory contests, vehicle spawning/dismounting, dispatch/MDT
  interaction, and purchase/refund flows under real concurrent load.
- Mobile and desktop UI on real devices rather than a resized Studio window.

## Verdict

**Not ready as it stands, for one reason:** three firearm passes are on sale
and deliver nothing. That is a live monetisation fault; the account holder is
handling it directly.

With those resolved, the two structural blockers from the previous pass
(untracked vehicle assets, `NetworkService` size) are closed, and hygiene
checks are all clean. What remains before a real release is the "not verified
in play" list above — that needs a staged two-player session, not more static
analysis.
