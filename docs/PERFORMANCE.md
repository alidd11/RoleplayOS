# Performance

Four separate questions decide whether this runs on a phone. They are often run
together as "optimisation" and they have different answers, different places
they are set, and different failure modes.

## 1. How far away does the world stop existing

`StreamingEnabled`, set in the project files under `Workspace`, because it
cannot be changed at runtime.

Without it every client downloads and permanently holds the entire city, every
vehicle in it, and all of their meshes, textures and sounds, whether or not the
player is anywhere near them. This is the setting people mean when they say a
game "only renders things near you".

| Property | Value | Why |
| --- | --- | --- |
| `StreamingTargetRadius` | 1024 | What is loaded when there is room. **The main dial to turn down if phones still struggle.** |
| `StreamingIntegrityMode` | `PauseOutsideLoadedArea` | Holds a player still rather than letting them fall through ground that has not arrived. The failure mode of streaming in a driving game is falling out of the world at speed. |
| `ModelStreamingBehavior` | `Improved` | Streams whole models, so a vehicle never arrives as a chassis without wheels. |

A spawned vehicle is `PersistentPerPlayer` and its driver is added to it, so it
stays loaded for the person driving and streams normally for everyone else.
Marking it persistent for everybody would put every vehicle in the server into
every client's memory, which is the cost streaming exists to avoid.

Workspace is marked `$ignoreUnknownInstances` in the project files. Rojo sets
these properties and does not touch the map, which does not live in this
repository and would otherwise be deleted as unmanaged.

> **`StreamingMinRadius` is not settable and is not listed above.** Studio's
> property grid shows it, but it is not scriptable: reading it from Lua throws
> "not a valid member of Workspace". That is why a Rojo sync leaves it at 64
> rather than applying it, and why reading it in a log line took down the
> service that was reporting on it.
>
> **Verify the rest in Studio rather than assuming the sync applied them.**
> Select `Workspace` and filter properties for `Stream`. Note that Studio
> **hides every dependent streaming property when `StreamingEnabled` is
> unticked**, so a short list there means the checkbox is off, not that the
> properties are missing.

## 2. What the world costs while it is here

`Config.Performance`, applied by `WorldBudgetService`.

Imported content answers this with the defaults of the tool it was exported
from, which are always the most expensive option. None of these are visual
decisions; each replaces "always the most expensive option" with "the expensive
option only when it is close enough to see".

| Setting | Default | What it fixes |
| --- | --- | --- |
| `MeshLevelOfDetail` | `true` | `Precise` meshes hold every triangle at every distance. `Automatic` is Roblox's own distance based detail. The largest single saving on an imported vehicle, because that is how modelling tools export. |
| `DisableLightShadows` | `true` | A shadow casting light costs far more than a light, and a lightbar is a dozen strobing at once. Lights still illuminate; they stop computing shadows. |
| `MaximumLightRangeStuds` | 60 | 0 leaves ranges alone. |
| `MaximumSoundDistanceStuds` | 400 | A siren with the default rolloff is mixed for every player in the server rather than for the ones near it. 0 leaves falloff alone. |
| `ModelLevelOfDetail` | `true` | Only touches models where the map explicitly turned distant detail **off**. Roblox's automatic choice is correct and is left alone, so this number is usually small. |

The startup pass is spawned and paced. Every service after it waits for `Start`
to return and the network endpoints are registered by the last of them, so a
walk that holds the frame is not a slow startup — it is a server that answers
nothing until it finishes.

Vehicles are normalised again as they are cloned, because templates live
outside the workspace and the startup pass never reaches them.

Watch the server log on startup for `World render budget applied`. It reports
what it changed rather than what it looked at.

## 3. What the server and the network cost

Profiles load once and save only when dirty, on a timed batch, leave or
shutdown. Static configuration is frozen and cached. The join catalogue sends
summaries rather than full profiles or full vehicle, property and furniture
catalogues. MDT results paginate and remote payloads are capped.

Runtime state uses events rather than DataStore or MemoryStore polling. Dispatch
messages contain only kind, stable ID and revision. Property interiors clone on
demand and unload after the last occupant and a safety delay. Server-only
definitions and templates do not replicate.

Team spawn pads use Roblox's native `TeamColor` and `RespawnLocation`
behaviour. Their `SpawnId` attributes are indexed once at startup; there is no
per-frame spawn scanning or position polling.

Dispatch seats and minimap geometry use `CollectionService` added and removed
signals. Dispatch state is pushed as small revision hints and fetched only when
an authorised interface is open. Phone calls are in-memory signalling records;
text history is bounded to the configured per-character limit. None of these
introduces a frame loop or a server polling loop.

There are three per-frame bindings in the whole framework: vehicle telemetry on
the server, which is throttled to `TrackingIntervalSeconds` and walks only
active vehicles, and the speedometer and driving controls on the client.

## 4. Reading the memory figure

**Studio's "Client Memory Usage" is not a client's memory.** It reports the
whole Studio process: the edit DataModel, the play DataModel, every plugin and
the editor. A real client loads one of those. A figure of several gigabytes in
Studio is expected and is not what a player sees.

Use the **Memory** tab rather than the headline number. It breaks down by
consumer, and the ones that matter here are `GraphicsTexture`,
`GraphicsMeshParts` and `Sounds`. Those three name whether the remaining cost is
textures, geometry or audio, which decides what is worth doing next.

Logger metadata is the instrumentation hook for everything else. Measure service
startup, persistence latency, remote rejection counts, catalogue sizes and live
instance counts before tuning.

## What is not fixed here

Content problems that need the place, not this repository:

- Assets owned by other accounts (`The experience doesn't have access permission
  to use asset id …`, `User is not authorized to access Asset`). These need
  re-uploading under the group. They are noise, but they are the large majority
  of the errors in the console and they bury the real ones.
- Third party vehicle scripts erroring per button per vehicle
  (`SirenControl … attempt to index nil with 'Body'`).
- A-Chassis tunes with `Density = 0`, which Roblox clamps and warns about once
  per part per vehicle.
