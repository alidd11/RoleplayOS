# Production test release — audit

State of the tree at `1759761`. Every claim below was re-checked against the
working tree at the time of writing rather than carried over from an earlier
pass. Verdict at the bottom.

## Blockers

### 1. Two firearm gamepasses take Robux and give nothing

| Pass | Gamepass id |
| --- | --- |
| `CivilianShotgun` | 1934518052 |
| `CivilianRifle` | 1934955986 |

`Config.EquipmentPasses` contains three entries and neither of these is among
them:

```lua
Knife   = { GamepassId = 1937446295, ToolNames = { "Knife" } },
ZKnife  = { GamepassId = 1949486956, ToolNames = { "ZKnife" } },
Machete = { GamepassId = 1949228959, ToolNames = { "Machete" } },
```

That table is what `LoadoutService:ApplyEquipmentPasses` reads to decide what a
pass hands over, so a pass absent from it is skipped silently. Neither has a
`Config.Tools` entry either, there is no firearm in the tool list at all, and no
firearm asset under `server-assets/Tools`.

A player who buys either receives an empty backpack. The comment above
`EquipmentPasses` records this exact fault being found once already, for the
ZKnife and machete passes, which "took 149 Robux for an empty backpack".

**Cannot ship with these on sale.** Delisting needs the account holder; building
the tools is not a test-release-sized job.

### 2. Three vehicle assets are untracked in git

```
server-assets/Vehicles/Civilian/Premium/72' BMW 545e.rbxm
server-assets/Vehicles/Civilian/Standard/23' Toyota Corolla HB.rbxm
server-assets/Vehicles/Civilian/Standard/24' Volvo V90.rbxm
```

Confirmed still untracked. Rojo maps `server-assets/Vehicles`, so all three sync
into the place and ship in the build, while being absent from version control. A
fresh clone therefore builds a different place than this one.

None has an entry in `EDIT_HERE/06_Vehicles.luau`, so none is reachable in game:
they are weight in the place file and nothing else. Either commit and wire them,
or move them out of `server-assets` until they are ready.

## Known defects, shipping unfixed

### 3. Vehicles launch on first dismount

Reported on the Peugeot van: it rises sharply and drops back.

All 163 of the van's parts are anchored in the template, with none free.
A-Chassis unanchors every one of them at initialise, and
`VehicleSpawnerService:_place` sets the vehicle down 0.75 studs above the bay, so
a rigid 163-part body is released into freefall as a single unit.

That clearance is deliberate. The comment above it records that placing an
imported pivot flat on the surface put wheels under the map and got assemblies
deleted, so it must not simply be set to zero.

Not diagnosed to conclusion, and specifically not explained why it happens on the
first dismount rather than at spawn. It will affect every A-Chassis vehicle,
since they share the unanchor path.

### 4. The Sur-Ron's air horn is a 113ms blip

Asset `691472063` at 0.113s, against the van's `416079906` at 2.46s. It is the
vehicle's own sound. The panel loops it while held so it sustains, but it still
sounds like a horn rather than an airhorn. Fixing it properly means swapping the
sound in the model and re-exporting.

Separately, both Sur-Rons carry siren volumes of 0.2 against the van's 1 to 8, so
the bikes are drastically quieter than the cars.

## Closed since the first pass

### 5. `renderCareers` — removed

Was an unreachable 240-line page with no `addNav` entry. Removing it uncovered
`narrowViewport`, a helper only that page used, which went with it. 256 lines
total.

`selene` now reports **0 errors and 0 warnings** on the tree, which it had not
done at any point during this work.

## Checked and sound

- **Rate limiting.** A global bucket at 30 capacity refilling 10/s, plus
  per-request buckets. `SetEmergencyLights` is 8 capacity refilling 3/s against a
  worst case of two requests per panel press, so the ELS paths sit inside it.
- **Remote validation.** 120 `type(payload...)` guards across `NetworkService`.
- **Persistence.** `DataService` uses `UpdateAsync` for shared keys and wraps
  DataStore and player calls in `pcall`.
- **ToS.** No references to controlled substances or alcohol anywhere in `src`.
  The offence and search-power checks grep for both by name, so neither can creep
  back silently.
- **Hygiene.** No `TODO`, `FIXME`, "not implemented" or "coming soon" markers.
  `stylua`, `selene` and `rojo build` all clean.
- **Tests.** An acceptance runner and harness exist under `tests/`.

## Not verified in play

Everything committed in this work was verified by build, lint, template sweep or
synthetic test. The following have never been observed running:

- ELS: `OFF` killing lights and siren, `999` starting the wail, `AT SCENE`
  lighting the work lamps
- The rebuilt panel rendering at its new size
- Accessories staying on the rider's head while mounted
- The R6 rig repair firing on a real dismount

The rig repair is the only one with a controlled test behind it: a synthetic R6
rig broken exactly as the moped breaks one, repaired, with a tool grip surviving.

## Verdict

**Not ready as it stands, for one reason:** the two firearm passes are on sale and
deliver nothing. That is a live monetisation fault and it needs the account
holder, not code.

With those delisted and the three loose vehicle assets resolved, the build is
sound enough for a test release. Items 3 and 4 are real but survivable: a vehicle
that jumps once on dismount is embarrassing rather than dangerous, and nothing
outstanding risks player data.

What a test release should actually be used for is the unverified list above. No
further static checking will resolve it.
