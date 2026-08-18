# Production test release — audit

State of the tree at `f01fda0`. Verdict at the bottom.

## Blockers

### 1. Two firearm gamepasses take Robux and give nothing

| Pass | Gamepass id |
| --- | --- |
| `CivilianShotgun` | 1934518052 |
| `CivilianRifle` | 1934955986 |

Neither is in `Config.EquipmentPasses`, which is the table
`LoadoutService:ApplyEquipmentPasses` reads to decide what a pass hands over.
Neither has a `Config.Tools` entry. There is no firearm of any kind in the tool
list, and no firearm asset under `server-assets/Tools`.

A player who buys either receives an empty backpack. This is the same fault the
`EquipmentPasses` comment records having already found once, for the ZKnife and
machete passes.

**Cannot ship with these on sale.** Delisting needs the account holder. The
alternative is building the tools, which is not a test-release-sized job.

### 2. Three vehicle assets are untracked in git

```
server-assets/Vehicles/Civilian/Premium/72' BMW 545e.rbxm
server-assets/Vehicles/Civilian/Standard/23' Toyota Corolla HB.rbxm
server-assets/Vehicles/Civilian/Standard/24' Volvo V90.rbxm
```

Rojo maps `server-assets/Vehicles`, so all three sync into the place and ship in
the build. None has an entry in `EDIT_HERE/06_Vehicles.luau`, so none is
reachable in game: they are weight in the place file and absent from version
control, which means a fresh clone builds a different place than this one.

Either commit them and wire them up, or move them out of `server-assets` until
they are ready.

## Known defects, shipping unfixed

### 3. Vehicles launch on first dismount

Reported on the Peugeot van: it rises sharply and drops back.

Every one of the van's 163 parts is anchored in the template. A-Chassis unanchors
all of them at initialise, and `VehicleSpawnerService:_place` sets the vehicle
down with 0.75 studs of clearance above the bay, so a rigid 163-part body is
released into freefall as a unit.

That clearance is deliberate - the comment above it records that placing an
imported pivot flat on the surface put wheels under the map and got assemblies
deleted - so it must not simply be set to zero.

Not diagnosed to conclusion. It will affect every A-Chassis vehicle, not only the
van, since they share the unanchor path.

### 4. The Sur-Ron's air horn is a 113ms blip

Asset `691472063` against the van's `416079906` at 2.46s. It is the vehicle's own
sound. The panel now loops it while held so it sustains, but it still sounds like
a horn rather than an airhorn. Fixing it properly means swapping the sound in the
model and re-exporting.

All four emergency vehicles also carry siren volumes of 0.2 on the Sur-Rons
against 1-8 on the van, so the bikes are drastically quieter.

### 5. `renderCareers` is unreachable

Declared and assigned in `DeveloperDashboard.luau`, never called, no `addNav`
entry. Roughly 240 lines drawing an "Emergency services" page the Play page now
supersedes. Harmless at runtime; should be deleted as its own change.

## Checked and sound

- **Rate limiting.** A global bucket at 30 capacity refilling 10/s, plus
  per-request buckets. `SetEmergencyLights` is 8 capacity refilling 3/s against a
  worst case of two requests per panel press, so the new ELS paths sit inside it.
- **Remote validation.** 120 `type(payload...)` guards across `NetworkService`.
- **Persistence.** `DataService` uses `UpdateAsync` for shared keys and wraps
  DataStore and player calls in `pcall`.
- **ToS.** No references to controlled substances or alcohol anywhere in `src`.
  The offence and search-power verification greps for both by name, so it cannot
  creep back silently.
- **Hygiene.** No `TODO`, `FIXME`, "not implemented" or "coming soon" markers.
  `selene` reports 0 errors and 1 warning, that warning being item 5 above.
  `stylua` and `rojo build` both clean.
- **Tests.** An acceptance runner and harness exist under `tests/`.

## Not verified in play

Everything committed this session was verified by build, lint, template sweep or
synthetic test. The following have never been observed running:

- ELS: `OFF` killing lights and siren, `999` starting the wail, `AT SCENE`
  lighting the work lamps
- The rebuilt panel rendering at its new size
- Accessories staying on the rider's head while mounted
- The R6 rig repair firing on a real dismount

The rig repair is the only one with a controlled test behind it: a synthetic R6
rig broken exactly as the moped breaks one, repaired, with a tool grip surviving.

## Verdict

Not ready as it stands, for one reason: **the two firearm passes are on sale and
deliver nothing.** That is a live monetisation fault and it needs the account
holder, not code.

With those delisted and the three loose vehicle assets resolved, the build is
sound enough for a test release. Items 3 to 5 are real but survivable in a test:
a vehicle that jumps once on dismount is embarrassing rather than dangerous, and
nothing in the list risks player data.

The thing a test release should actually be used for is the unverified list
above, which no amount of further static checking will resolve.
