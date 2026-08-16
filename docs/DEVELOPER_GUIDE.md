# RoleplayOS developer guide

This is the onboarding document for a developer who knows Roblox and Luau but has
never opened this repository. It explains the shape of the project, the two
composition roots, the rules the framework enforces on you, and the recipes for
the jobs you will actually be asked to do.

It complements rather than repeats the existing documents. [Architecture](ARCHITECTURE.md)
states the design in one page, [Project structure](PROJECT_STRUCTURE.md) is the
canonical folder map, [Content authoring](CONTENT_AUTHORING.md) is the full
certification checklist, and [Security](SECURITY.md) and [Access control](ACCESS_CONTROL.md)
own the trust boundaries. Read `AGENTS.md` at the repository root before your
first change; it is short and it is binding.

## 1. Orientation

### Rojo and what ends up where

There are three Rojo projects. `default.project.json` is the one you use daily
and the one CI builds. `real-baseplate.project.json` is the same mapping with
`$ignoreUnknownInstances` set everywhere, for syncing into an existing map
without Rojo deleting the map; see [Real baseplate deployment](REAL_BASEPLATE_DEPLOYMENT.md).
`acceptance.project.json` additionally maps `tests`, which `default.project.json`
deliberately does not, so test scripts can never reach a production place.

The default mapping, and the renames you need to know about:

| On disk | In the DataModel |
|---|---|
| `src/shared/Utility` | `ReplicatedStorage.RoleplayOS.Shared` |
| `src/shared/Config` | `ReplicatedStorage.RoleplayOS.Config` |
| `src/shared/Types` | `ReplicatedStorage.RoleplayOS.Types` |
| `src/shared/Network` | `ReplicatedStorage.RoleplayOS.Network` |
| `src/server/Services` | `ServerScriptService.RoleplayOS.Services` |
| `src/server/Systems` | `ServerScriptService.RoleplayOS.Systems` |
| `src/server/Bootstrap.server.luau` | `ServerScriptService.RoleplayOS.Bootstrap` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.RoleplayOSClient` |
| `server-assets/*` | `ServerStorage.RoleplayOSAssets.*` |
| `server-assets/ImportedSources/*.rbxm` | `ServerStorage.RoleplayOSImportedSources.*` |

Two of those will trip you up. `Utility` becomes `Shared`, so
`require(ReplicatedStorage.RoleplayOS.Shared.Logger)` is `src/shared/Utility/Logger.luau`
on disk. And `src/client` contains `init.client.luau`, so Rojo turns the whole
directory into a single `LocalScript` named `RoleplayOSClient` with `Controllers`,
`UI` and `Systems` as its children; that is why client code says
`require(script.Controllers.X)` rather than reaching for a sibling folder.

`ReplicatedStorage.RoleplayOS.Network` is mapped from an empty directory on
purpose. It is where the server creates the `Remotes` folder at runtime, and
mapping it with `$ignoreUnknownInstances` keeps Rojo from deleting remotes it did
not create.

### src/server

`Services` holds one authoritative gameplay domain per file, named
`<Domain>Service.luau`. There are seventy-seven of them and they are all listed,
in dependency order, in `Bootstrap.server.luau`.

`Systems` holds the framework infrastructure the services sit on: `ServiceRegistry`
(lifecycle), `NetworkServer` (the remote gateway), `ToolFactory` (built-in Tool
fallbacks), `TextFilter` and `WebCallPacer`. These are plain modules, not services;
they are constructed by the bootstrap or required directly by services.

### src/client

`Controllers` holds feature and input controllers, `UI` holds the reusable visual
modules they mount, and `Systems` holds client systems that are constructed with
`.new` rather than lifecycled. `AudioFeedback` is constructed by the composition
root and shared through the context; `AssetPreloader` is required directly by
`DeveloperDashboard`, which is the only thing that needs it.
`init.client.luau` is the composition root.

### src/shared

Replicated, dependency-free where practical, and reachable by both sides.
`Utility` is pure logic and validators — `AccessEvaluator`, `RateLimiter`,
`Response`, `ProfileSchema`, `ConfigValidator` and so on. Nothing here may hold
server secrets or mutable server state, because all of it replicates to clients.
`Types` holds `DomainTypes.luau`.

`src/shared/Constants` exists on disk but is empty and is not mapped by any Rojo
project. Treat it as vestigial rather than as a place to put things.

### Config.luau versus EDIT_HERE

`src/shared/Config/Config.luau` is around 2,300 lines of framework defaults and
catalogue: teams, roles, departments, tools, loadouts, jobs, dealerships,
progression, network limits, content-quality budgets. You edit it when you are
changing framework behaviour or adding a new kind of thing.

`src/shared/Config/EDIT_HERE` is the routine configuration surface, numbered so
it stays findable in Studio's Explorer:

- `01_Deployment` — environment, branding, integrations, Studio mock switches
- `02_Groups` — Roblox community IDs and minimum ranks
- `03_Gamepasses` — production pass and developer-product IDs
- `04_Uniforms` — shirt and trouser template IDs
- `05_Balancing` — starting money, character slots, common timings
- `06_Vehicles` — the live vehicle catalogue and dealership forecourts

At the bottom of `Config.luau`, each of those modules is required and applied
over the defaults by a recursive merge (`applyOverride`). Two consequences worth
knowing:

- The merge walks tables key by key, and an **array is a table whose keys are 1,
  2, 3**. Overriding a list therefore replaces its elements positionally rather
  than appending, which is why `06_Vehicles` writes out whole forecourt lists.
- The merge **adds** keys that the defaults do not contain, so an entirely new
  gamepass or vehicle can live only in `EDIT_HERE`. `03_Gamepasses` has a worked
  example of this in the `SurronBike` entry.

`Config.Vehicles` and `Config.Dealerships` are explicitly emptied just before the
merge, so the vehicle catalogue is whatever `06_Vehicles` says it is and nothing
else. After the merge, `Config.luau` rewrites gamepass IDs referenced inside role
and vehicle access rules, so changing one ID in `03_Gamepasses` cannot leave half
an entitlement pointing at the old pass. Finally it merges `AssetManifests.luau`
into `ContentQuality.CertifiedAssets` (see section 5) and `table.freeze`s the
whole thing.

`EDIT_HERE` sits **beside** `Config.luau` on disk, so in the DataModel they are
siblings inside the `Config` folder, not parent and child. The lookup in
`Config.luau` handles both, but if you move files around, remember that every
controller requires this module: a configuration that fails to load means a
client with no interface at all.

### Studio content versus git

Nearly every model in this game is imported, and imported models are large binary
assets. Git holds the folder skeleton — `server-assets/**` is mostly `.gitkeep`
files — plus a small number of committed `.rbxm` sources under
`server-assets/ImportedSources` and one or two templates such as the Corolla taxi.
`.gitignore` blocks `*.rbxm` everywhere except `server-assets`, which is the
deliberate exception.

The real content lives in the Studio place, under `ServerStorage.RoleplayOSAssets`,
in the folder layout described by `server-assets/README.txt` and
[Content authoring](CONTENT_AUTHORING.md). That means:

- A clean checkout will not have the vehicles. The server reports missing
  templates as warnings in Development and refuses to start in Production.
- What git *does* hold about those assets is their configuration entry and their
  certification manifest. Those two are the reviewable record of an import.
- `server-assets/UI/RoleTiles` holds the source PNGs for the start-menu role
  artwork. It is not mapped by any Rojo project, because images cannot be synced
  as instances: they are uploaded to Roblox and reach the game as asset IDs, the
  role tiles among them preloaded through `Config.AssetPreload.Background`.

## 2. The service model

### Shape of a service

A service is a module returning a table with up to four lifecycle members. The
smallest real example in the tree is `UKTimeService`:

```lua
--!strict
local ExampleService = { running = false }

function ExampleService:Init(context: any)
	self.context = context
end

function ExampleService:Start() end

function ExampleService:Destroy()
	self.running = false
end

return ExampleService
```

`Init` stores dependencies and registers infrastructure. It must not begin work,
because every other service's `Init` still has to run. `Start` connects events and
begins work. **`Start` receives no arguments** — the registry calls
`service.Start(service)` — so anything you need from the context must have been
saved in `Init`. `Destroy` releases connections and state.

### The context object

The bootstrap builds one context and hands the same table to every service:

- `Logger` — the shared logger; `Info`, `Warning`, `Error`, `Security`
- `Configuration` — a shallow-cloned, *mutable* runtime catalogue, not the frozen
  `Config` module. This exists because imported-content discovery registers
  vehicles and tools that no configuration file declares, and a validator must
  not be editing a required module to do that.
- `Services` — the registry
- `Sessions` — per-server session table
- `Network` — the `NetworkServer` instance

### The Critical flag

Set `Critical = true` on the service table if the server must refuse to run
without it. Everything else is degradable by default, and that default is the
important part. `ServiceRegistry:_handleFailure` steps over a non-critical service
that throws in `Init` or `Start`: it is recorded in `Failed()`, logged as "Service
failed and was stepped over", and left registered so callers still reach it and
fail one request at a time, which the network layer already catches and reports.

The reasoning is written out in `ServiceRegistry.luau` and is worth taking
seriously: a server with no dealership is a server with no dealership, but a
server with no `DataService` quietly loses everything its players do, and a server
with no `AccessService` cannot be trusted about who is allowed on which team. Only
that second kind justifies refusing to run. Thirteen services currently carry the
flag, including `DataService`, `AccessService`, `TeamService`, `NetworkService`,
`GamepassService`, `DeveloperProductService` and `ContentValidationService`.

Note that `AGENTS.md` describes this as `Optional = true`. That is stale wording;
the code reads `Critical` and the default is optional.

### Finding other services

Never `require` another service module. Ask the registry:

```lua
local economy = self.context.Services:Get("EconomyService")
```

Every service is registered before any `Init` runs, so `Get` resolves at any point
after registration and cannot produce a require cycle. What order buys you is
*readiness*: a service earlier in the list has already initialised and started, so
its state is usable. That is why `DataService` is first and `NetworkService` is
second from last.

If you `Get` a name that was never registered, the registry asserts with "Unknown
service", which is a startup failure rather than a silent nil.

### Startup and shutdown

`Bootstrap.server.luau` validates the configuration, builds the context,
registers every service in `serviceOrder`, arms `BindToClose` **before** starting
anything, then runs `Initialise` followed by `Start` inside one `pcall`. If a
critical service fails, the teardown runs and every player — present and future —
is kicked with a deliberately generic message; the real diagnostic stays in the
server log, because returning service paths to a player turns a safe refusal into
an architecture disclosure.

`Destroy` runs in reverse registration order, so `DataService`, registered first,
is destroyed last and writes profiles after everything else has stopped changing
them. The teardown is armed before startup because a service that threw during
registration used to take the script down before `BindToClose` was ever bound,
which meant no `Destroy` ran at shutdown and players lost everything since their
last autosave.

### Adding a service

1. Create `src/server/Services/<Domain>Service.luau` with `Init`, `Start` and
   `Destroy`. Add `Critical = true` only if the server is untrustworthy without it.
2. Add its name to `serviceOrder` in `Bootstrap.server.luau`, positioned after
   everything it needs to be ready. Registration is explicit; a file that is not
   in the list is dead code.
3. If it owns remote endpoints, follow section 4.
4. If it owns persistent state, route it through `DataService` — that is the only
   module permitted to touch DataStores, exactly as `EconomyService` is the only
   module permitted to change balances.

Place it before `NetworkService` if endpoints registered there call into it, and
before `HealthService`, which reports last on purpose.

## 3. The client model

### Shape of a controller

Same three-phase lifecycle as a service, with a different context:

```lua
--!strict
local ExampleController = {}

function ExampleController:Init(context: any)
	self.context = context
end

function ExampleController:Start() end

function ExampleController:Destroy() end

return ExampleController
```

The client context is `{ Controllers, Events, Systems }`. `Controllers` is the
table of every controller, so one controller reaches another as
`self.context.Controllers.UIOrchestrator`. `Events` is a set of named
`BindableEvent`s parented to the client script (`StartMenuChanged`,
`DispatchChanged`, `SettingsChanged`, `CharacterChanged`, `DutyChanged`,
`VehicleModeChanged`, `UIStateChanged`). `Systems` holds the instantiated client
systems.

`FeatureController.new(name)` produces a minimal view-model holder, used for the
six placeholder features (`AccessPrompts`, `Jobs`, `Vehicles`, `Properties`,
`Furniture`, `EmergencyServices`). If you are building one of those out properly,
replace the generated controller with a real module.

### The ORDER list

`init.client.luau` builds the `controllers` table by requiring each module, then
drives both lifecycle phases from a single `ORDER` list. One list, not two,
because keeping two in sync by hand eventually produces a controller that is
initialised and never started.

**A controller that is required but missing from `ORDER` is never initialised at
all.** Adding a controller therefore means two edits in the same file: the
`controllers` table and `ORDER`.

The two phases behave differently, and the difference matters:

- **Init is serial and in order**, because controllers read each other's stored
  dependencies. Each call is wrapped in its own `pcall` so one bad controller
  warns instead of killing the script and leaving a blank screen. Init must not
  touch the network or wait on anything — the start menu is mounted after this
  loop finishes, so time spent here is time the player spends looking at nothing.
  `NetworkController:Init` deliberately does no lookups for this reason.
- **Start is spawned per controller**, isolated the same way, because `Start`
  connects events and issues first requests and may legitimately yield on a
  remote the server has not registered yet. One slow or hung controller must not
  hold up the rest of the interface.

The three entries in `systemModules` — `NotificationSystem`, `ModalSystem`,
`AudioFeedback` — are constructed with `.new(context)` during the Init pass and
have no `Start`. They are first in `ORDER` so later controllers can pull them off
`context.Systems`.

`DeveloperDashboard` (the start menu) is mounted last, in a `pcall` of its own,
because it is the thing the player actually looks at and its failure should say
so rather than vanish.

### UIOrchestrator, layouts and SafeViewport

`UIOrchestrator` is the single source of truth for how much screen an interface
may use. It computes a `Layout` and publishes it two ways: as attributes on
`PlayerGui` (`RoleplayOSBreakpoint`, `RoleplayOSUIState`, `RoleplayOSInputMode`
and friends) and to callbacks registered with `Bind`.

```lua
self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Speedometer", function(layout)
	-- called immediately with the current layout, then on every change
end)
```

`Bind` returns an unbind function — call it in `Destroy`. `GetLayout()` gives a
one-off snapshot. `FitScale(layout, design, margin)` returns the `UIScale` factor
that keeps a panel authored at a fixed pixel size, plus its margin, inside the
usable area.

Layouts are recomputed when the viewport, `TopbarInset`, `PreferredTextSize`,
last input type or VR state changes.

Breakpoints are `VR`, `Compact` (usable width under 700 **or** usable height
under 500), `Tablet` (usable width under 1050) and `Desktop`. Both axes are
tested because Roblox runs phones in landscape: a current large phone is roughly
932 by 430, which is wider than the tablet threshold while having barely half a
tablet's height. Classifying on width alone called that a tablet and handed
sixteen panels the wrong sizes.

**Size and scale panels against `layout.SafeViewport`, never `layout.Viewport`.**
`SafeViewport` is the viewport minus the reserves Roblox needs for the top bar,
notches, Dynamic Islands, rounded corners and home indicators. Those reserves are
measured from the difference between `GuiService:GetInsetArea(None)` and
`GetInsetArea(CoreUISafeInsets)`, which is why there is no device-specific
constant anywhere in the interface, and why the calculation degrades to the
top-bar band on older clients that lack the method. A panel sized against the raw
viewport is not merely a bit large: it spills under the reserved regions and is
clipped, and the part that gets clipped is usually an edge control.

The related values on the same layout are `NativeTop` and `NativeLeft` (measured,
not assumed, because Roblox moves its own control cluster), `HudScale` for the
ambient heads-up display, `HotbarBottom` and `RightReserve`.

More on the visual language, VR rules and motion budgets in
[Interface system](UI_SYSTEM.md).

### Talking to the server

`NetworkController:Request(endpoint, payload)` yields and always returns a table,
never nil. Beyond the server's own codes it can produce `ENDPOINT_UNAVAILABLE`
(the remote never appeared), `REQUEST_TIMEOUT` (no reply within 14 seconds) and
`NETWORK_ERROR`. It resolves remotes lazily and shares one bounded wait between
all callers, so a hundred controllers starting at once produce one wait rather
than a hundred. `ResolveEvent(name)` does the same for `RemoteEvent`s.

## 4. Adding a network endpoint

### The registration

Endpoints are registered on the gateway during a service's `Start`, conventionally
in `NetworkService` (which is `Critical` and runs second from last, so every
domain service exists by then). Registering elsewhere is allowed and the
rate-limit checker will still find it.

```lua
self.context.Network:RegisterFunction("DropCash", function(payload)
	return type(payload) == "table" and type(payload.Amount) == "number"
end, function(player, payload, requestId)
	local result, reason = self.context.Services:Get("MoneyDropService"):Drop(player, payload.Amount)
	return {
		Success = result ~= nil,
		Code = if result then "OK" else reason,
		Message = if result then "Cash dropped." else "Cash could not be dropped.",
		Data = result,
		RequestId = requestId,
	}
end)
```

### The validator

The second argument is a pure predicate: `(payload) -> boolean, string?`. Return
`false` and, optionally, a short machine reason. It is called inside a `pcall`, so
a validator that throws is treated as `SCHEMA_ERROR` and the request is refused —
but do not rely on that; write the validator so it cannot throw.

Validate shape only. Do not put authority decisions here: whether the player may
do the thing is the domain service's job, re-evaluated server-side on every call.
`tablePayload` and `boundedStringArray` at the top of `NetworkService.luau` are
the shared helpers.

### The response shape

Handlers are `(player, payload, requestId) -> table` and must return:

| Field | Meaning |
|---|---|
| `Success` | boolean |
| `Code` | machine-readable outcome; `"OK"` on success |
| `Message` | player-facing, British English, safe to display |
| `Data` | the DTO, containing only the fields the client needs |
| `RequestId` | echo the `requestId` argument |

`src/shared/Utility/Response.luau` provides `Response.ok(data, requestId)` and
`Response.error(code, message, requestId)` for the common cases. The gateway
overwrites `RequestId` on the way out regardless, and rejects a handler that
returns a non-table as `SERVER_ERROR`.

Keep the `Message` free of internal detail. `Code` is for the client to branch
on; `Message` is for the player to read.

### What the gateway does around your handler

In order: global token bucket, then the endpoint's own bucket
(`RATE_LIMITED`); the server-entry authorizer, which refuses anyone whose
access check is still running (`ACCESS_PENDING`); `PayloadInspector` structural
limits on depth, node count and string size (`PAYLOAD_REJECTED`); a JSON encode
against `MaximumPayloadBytes` (`PAYLOAD_REJECTED`); your validator
(`INVALID_REQUEST`); per-player and per-server concurrency (`SERVER_BUSY`); then
your handler, run alongside an 8-second deadline (`SERVER_TIMEOUT`) and a `pcall`
(`SERVER_ERROR`).

The deadline is why every endpoint should answer in well under a second. The
server always replies, even if the handler is still running, because
`InvokeServer` cannot be cancelled and a stalled handler otherwise leaves the
player staring at a button that never comes back.

For server-to-client pushes use `RegisterEvent(name)`, which returns a
`RemoteEvent`. `NetworkService:Start` calls `Network:MarkReady()` after the last
registration, which is what lets a client tell "the server is still starting"
apart from "this endpoint does not exist".

### The rate limit is mandatory

Every `RegisterFunction` needs a matching entry in `Config.Network.Endpoints`:

```lua
DropCash = { Capacity = 3, RefillPerSecond = 0.2 },
```

`RegisterFunction` asserts if the entry is missing. Since `NetworkService` is
`Critical`, a forgotten rate limit is not a warning — it is a server that will not
start. That is deliberate: an unlimited endpoint is a denial-of-service vector and
the framework would rather refuse to run than expose one.

Choose the numbers from what the call costs, not from what feels generous.
`Capacity` is the burst; `RefillPerSecond` is the sustained rate. The existing
entries are commented with their reasoning and are a good guide — a cheap read
answered from a table gets `{ Capacity = 4, RefillPerSecond = 1 }`, something that
reaches Roblox's catalogue and spends a server-wide quota gets a tighter refill,
and something that spends money or writes a record gets `{ Capacity = 2,
RefillPerSecond = 0.1 }` or slower.

`scripts/validate-network-limits.py` enforces this and runs inside
`validate-structure.sh`. It scans every `.luau` file under `src/server` for
`RegisterFunction("Name"` and `Config.luau` for `Name = { Capacity =`, and
requires an exact one-to-one correspondence. It fails on a missing limit, a
**stale** limit whose endpoint no longer exists, and duplicates on either side.

Because it is a regular-expression scan, the endpoint name must be a string
literal in the `RegisterFunction` call and the limit entry must have `Capacity`
as its first key on the same line as the name. Both conventions are already
universal in the codebase; follow them and the checker will see your endpoint.

## 5. Importing content

This is the section that matters most here, because almost nothing in this game
is built from scratch. Vehicles, tools, radios, lighting kits and world props are
imported, and imported content arrives full of scripts.

### Step 1: install the asset at its declared AssetPath

Every vehicle and tool definition carries an `AssetPath`, which is a list of
folder names **relative to `ServerStorage.RoleplayOSAssets`**:

```lua
Handcuffs = {
	Id = "Handcuffs",
	AssetPath = { "Tools", "Services", "Police", "Shared", "Handcuffs" },
	DepartmentId = "Police",
},
```

Install the model or Tool at exactly that path in Studio. `ContentValidationService`
resolves the path child by child; a mismatch is reported as a missing template —
a warning in Development, and fatal in Production.

You can also add content by folder placement alone. `ContentValidationService`
discovers undeclared models and Tools under the standard folders and registers
them at runtime, which is why the context carries a mutable `Configuration`
catalogue. Service-folder placement determines department, team and eligible roles
automatically. A configured entry with the same ID stays authoritative and must
point at the same folder.

The template itself has to be structurally sound: a vehicle must be a `Model`
containing a `VehicleSeat`, a `Tool` with `RequiresHandle` must contain a
`Handle`, and both must be within the part and descendant budgets in
`Config.ContentQuality`. A `RoleplayOSAssetId` attribute, if present, must match
the configured ID.

### Step 2: understand why certification exists

`ContentValidationService` treats ten classes as unsafe inside a template:
`Script`, `LocalScript`, `ModuleScript`, `RemoteEvent`, `RemoteFunction`,
`UnreliableRemoteEvent`, `BindableEvent`, `BindableFunction`, `ProximityPrompt`
and `ClickDetector`.

A rule that simply forbade all of them would be unusable here. A single imported
vehicle carries somewhere between seventeen and forty-five executables across its
chassis, its lighting kit and its sound system, and it cannot drive without them.
A rule that is bypassed on every asset protects nothing and blocks everything.

So the framework does something narrower: it pins an **inventory**. A manifest
records the exact set of executables an asset contained at the moment it was
accepted, matched by name, class and path. Anything that appears afterwards — a
backdoor added to a model, a script introduced by a marketplace update, an edit
nobody meant to publish — fails validation and names itself, instead of running
unnoticed on the live server.

Be clear about what that is and is not. **It is provenance and tamper detection.
It is not a claim that anybody read the scripts.** The `ReviewedBy` line on a
generated entry says so in plain words, and it must stay honest.

### Step 3: generate the manifest in Studio

`scripts/generate-asset-certification.studio.luau` runs from the Studio Command
Bar while **not** play-testing. Set the two constants at the top:

```lua
local TARGET_PATH = { "RoleplayOSAssets", "Vehicles", "Services", "Transport", "CorollaTaxi" }
local ASSET_ID = "CorollaTaxi"
```

`TARGET_PATH` is resolved from `game`, so it starts at the `ServerStorage` child.
`ASSET_ID` must be the configured stable ID, because that is the key the validator
looks the manifest up by.

The script walks every descendant, collects those matching the forbidden set,
groups them by name (a repeated name is emitted as a list, which the validator
accepts) and prints a ready-to-paste block plus a count.

### Step 4: paste it into AssetManifests.luau

Paste the printed block into `src/shared/Config/AssetManifests.luau`, then
**correct the three placeholder lines**: `Source` to where the asset genuinely
came from, `RealWorldReference` to the specific UK object it is modelled on, and
`ReviewedBy` to what was actually done. The generator's default `ReviewedBy`
already says "not a line-by-line source review"; leave that wording unless you
really did read the source.

The generator's own header says to paste into `ContentQuality.CertifiedAssets` in
`Config.luau`. That is where the entry ends up, but it gets there via the merge at
the bottom of `Config.luau`, which copies every key from `AssetManifests.luau` into
`ContentQuality.CertifiedAssets`. New generated entries belong in
`AssetManifests.luau` — the vehicles alone would otherwise add several hundred
lines of generated path tables to the middle of the file people actually edit. An
entry written by hand in `Config.luau` always wins, so a hand-written
certification is never silently replaced by a regenerated manifest.

Note that a manifest **supersedes** the asset's own attributes. When
`qualityIssue` finds a manifest for the configured ID, it reads `Certified`,
`ReviewVersion`, `Source`, `RealWorldReference` and `ReviewedBy` from the manifest
and ignores the attributes entirely. This is intentional: attributes on binary
assets do not round-trip reliably through Rojo, and the manifest is the copy that
lives in git and can be reviewed in a diff.

`ReviewVersion` must equal `Config.ContentQuality.CertificationVersion`, currently
`1`. Bumping that version invalidates every certification at once, which is the
mechanism for forcing a re-review.

### Step 5: re-run the place and read the report

Start the server and confirm the asset no longer reports `UNSAFE_<CLASS>`. The
other failure codes you may see are `CERTIFICATION_REQUIRED`,
`CERTIFICATION_VERSION_INVALID`, `ASSET_SOURCE_REQUIRED`,
`REAL_WORLD_REFERENCE_REQUIRED`, `REVIEWER_REQUIRED`, `PART_BUDGET_EXCEEDED`,
`DRIVER_SEAT_REQUIRED`, `HANDLE_REQUIRED`, `WRONG_CLASS` and `CONFIG_ID_MISMATCH`.

`scripts/audit-imported-assets.studio.luau` gives the same picture from Studio
without starting a server.

### When a previously-passing asset starts failing

This is the case the whole mechanism exists for. **An unexpected validation
failure means the asset changed.** Investigate what changed and why before doing
anything else. Regenerating the manifest to make the error go away silences
precisely the signal you built it to receive, and it is exactly how a backdoor
introduced by a marketplace update would get waved through.

Regenerate when you have deliberately updated the asset and understand the
difference. Otherwise, treat it as a real question about the asset.

### Related boundaries

`ContentValidationService` is `Critical`, and `validate-structure.sh` greps for
`Critical = true` inside it and fails the build if the flag is removed. Unsafe
imported assets are not an optional feature failure.

Imported vehicles may keep their driving chassis, but competing ELS kits, siren
panels, payroll scripts, unauthorised remotes and stray sounds must not ship. The
one-time `quarantine-legacy-vehicle-controls.studio.luau` utility moves the known
offenders to `ServerStorage/RoleplayOSLegacyVehicleQuarantine` rather than
deleting them, so rollback stays possible while the scripts stop running.
Production refuses to start while the quarantine still holds anything.

World props are certified separately; see the world-objects section of
[Content authoring](CONTENT_AUTHORING.md) and the ledger in
[World asset certification](WORLD_ASSET_CERTIFICATION.md).

## 6. Common tasks

### Add a vehicle

1. Install the model in Studio under
   `ServerStorage/RoleplayOSAssets/Vehicles/...`, in the folder matching its
   category (`Civilian/Starter|Standard|Premium`, or `Services/<Department>`).
   It must be a `Model` containing a `VehicleSeat`.
2. Certify it (section 5). Imported chassis mean a generated manifest entry.
3. Declare it in `src/shared/Config/EDIT_HERE/06_Vehicles.luau` under `Vehicles`,
   with `Id`, `Name`, `Price`, `ModelName`, `AssetPath`, `Colours`, `Category`
   and either `Access` (civilian) or `TeamName`/`DepartmentId`/`DivisionId`/
   `RoleIds` (service). Add `WorkspaceModelName` if a Studio installer or the
   emergency-lighting pass has to find the model by its Workspace name.
4. To put it on a forecourt, edit the relevant `Dealerships` entry in the same
   file — and write out the **whole** `VehicleIds` list, because the merge
   overwrites arrays positionally.
5. A service vehicle carries `Price = 0`: it is issued by the role, not bought.

An undeclared vehicle dropped into the right folder is discovered at runtime and
priced by a `Price` **number attribute** on its top-level `Model`. Use one source
of truth per vehicle: a configured entry's price wins, so do not also set the
attribute. Optional attributes are `DisplayName`, `DefaultColour`, `DealershipId`,
`GamepassId` and `RoleplayOSAssetId`.

### Add a tool

1. Install the `Tool` under `ServerStorage/RoleplayOSAssets/Tools/...`. `Shared`
   is eligible for every service loadout; a department or police-division folder
   restricts it to matching loadouts; `Civilian` registers it without adding it to
   any service loadout. Set `AutoEquip = false` for locker-only tools.
2. Certify it.
3. Declare it in `Config.Tools` with `Id`, `AssetPath` and `DepartmentId`. Add a
   `Weapon = { Damage, Cooldown, Range }` table if it is a melee weapon —
   `MeleeWeaponService` owns damage, range, line of sight, cooldown, death
   cleanup and police seizure on the server, which is why a damage script inside
   the Tool would be both duplicated and exploitable.
4. Add its ID to the relevant `Config.Loadouts` entry so a role actually receives
   it.
5. `BuiltInFallback` names a shape `ToolFactory` can build without geometry
   (`MDT`, `Radio`, `Handcuffs`, `MedicalBag`, `Weapon`). A tool with a valid
   fallback and no template reports as ready rather than missing, because the
   framework will issue something usable. Declaring a fallback the factory cannot
   build reports as missing, which is the point.

### Add a role or team

Teams first: add an entry to `Config.Teams` with `Id`, `Name`, `BrickColor` and
`AutoAssignable`. `TeamService` creates the Roblox `Team` at startup if it does
not exist and sets its colour, so you do not add Teams by hand in Studio — but it
errors if the name is already taken by a non-`Team` instance.

Then the role, in `Config.Roles`. The shape, with an illustrative ID:

```lua
DogHandler = {
	Id = "DogHandler",
	Name = "Dog Handler",
	TeamName = "Police",
	DepartmentId = "Police",
	DivisionId = "DogSection",
	Access = { AccessType = "Group", GroupLinkId = "Police", MinimumGroupRank = 1 },
	LoadoutId = "PoliceResponse",
	UniformId = "PoliceStandard",
},
```

`Access` is evaluated by `src/shared/Utility/AccessEvaluator.luau`. The available
`AccessType` values are `Public`, `ServerKind` (`Kind` or `Kinds`), `Gamepass`,
`Application`, `Group`, `Rank`, `Qualification`, `Department`, `Whitelist`,
`Staff` and `Combined` (with `Match = "Any"` or `"All"`). `DisplayWhenLocked`
keeps the card visible in the menu while it is unavailable, which is usually what
you want — a role that vanishes is indistinguishable from a bug.

The `publicPassOr(rule, gamepassId)` helper near the top of `Config.luau` builds
the common two-tier shape: a pass on the public place, or the given rule anywhere
else. Use it rather than hand-writing the nested `Combined` rule.

A role inherits its department's permissions unless it states its own
`Permissions` list. State them explicitly whenever the role is deliberately
weaker than its department — the PCSO entry is the worked example, and its comment
explains why: inheriting Police handed a free public role warrant creation,
custody booking, search, escort and the blue-light exemption.

Add a matching `Config.Loadouts` entry and a `Config.Uniforms` template ID if the
role needs either.

### Add a gamepass

1. Create the pass in Creator Hub and set its price there. Nothing in this
   repository can publish a catalogue change.
2. Add or override the entry in `src/shared/Config/EDIT_HERE/03_Gamepasses.luau`
   under `Gamepasses`. Overriding an existing pass needs only
   `{ GamepassId = ..., PriceInRobux = ... }`; a brand-new pass can be defined in
   full there, because the merge adds keys the defaults do not hold.
3. `GamepassId = 0` disables purchasing and entitlement for that entry without
   breaking the menu, which is the correct placeholder while the pass does not yet
   exist. The item shows as locked and simply cannot be bought.
4. Reference it from an access rule with `{ AccessType = "Gamepass", GamepassId = ... }`,
   or from a vehicle's `GamepassId`. Editing the ID in `03_Gamepasses` rewrites
   those references automatically, so you do not have to hunt them down.
5. Run `python3 scripts/audit-gamepasses.py` to check every configured ID against
   the live Roblox API for creator, for-sale status and a positive price. It is
   read-only and needs network access.

### Add a developer product

1. Create the one-time product in Creator Hub.
2. Add the definition to `Config.DeveloperProducts` with `Id`, `ProductId`,
   `GrantType`, `Amount`, `Name`, `Description` and `PriceRobux`, and put the real
   `ProductId` in `03_Gamepasses.luau` under `DeveloperProducts`.
3. Teach `DeveloperProductService` what the grant means. Counted consumables are
   listed in its `COUNTED_GRANTS` table as a profile field plus an audit action;
   a new `GrantType` without an entry there will not be granted.
4. `DeveloperProductService` is the sole owner of `ProcessReceipt`. Do not add a
   second one. It records the grant and saves before returning
   `PurchaseGranted`, and rolls the balance back untouched if the save fails, so a
   receipt is never marked processed against a grant that did not reach the store.
   Receipts arriving outside a Public server return `NotProcessedYet` and wait,
   because public and whitelisted profiles are deliberately separate.

## 7. Verification

Run all of these before committing. CI runs the same set, so a failure here is a
failure there.

```sh
stylua --check src tests
selene src tests
bash scripts/validate-structure.sh
rojo build default.project.json --output build/RoleplayOS.rbxlx
python3 scripts/validate-network-limits.py
```

- `stylua --check` fails on formatting drift; `stylua src tests` fixes it in
  place.
- `selene src tests` is the linter, configured by `selene.toml`.
- `validate-structure.sh` checks that the required paths exist, that
  `ContentValidationService` is still `Critical`, and then runs both Python
  validators. It forwards its arguments, so `bash scripts/validate-structure.sh --production`
  reaches the stricter deployment gate rather than being swallowed.
- `rojo build` catches a project file that no longer matches the tree — a renamed
  or moved module, most often.
- `validate-network-limits.py` is already run by the structure script; run it on
  its own while you are iterating on endpoints, because it is instant and its
  output names the offending endpoint.

Before a publish, follow the [release-readiness gate](RELEASE_READINESS.md) and
the runtime checks in [Staging acceptance](STAGING_ACCEPTANCE.md). CI does not
claim to run Roblox-runtime tests on a generic Linux runner: `tests/run.luau`
needs a Roblox runtime, mapped by `acceptance.project.json`, and must be run in
Studio or a pinned Roblox-compatible runner. See [Testing](TESTING.md).

Two more habits from `AGENTS.md` worth restating, because both are invisible until
they bite: add a migration whenever a persistent shape changes, and update the
owning subsystem document whenever a contract changes. Stable IDs and content
folder paths are persistent contracts — changing one without a migration can make
an owned vehicle, Tool or role appear to have vanished from a player's profile.
