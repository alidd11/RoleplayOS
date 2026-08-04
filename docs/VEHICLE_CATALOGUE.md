# Adding vehicles

Put the model in the right folder. That is the whole process — there is no list
to update and no configuration to write.

## Where things go

Everything lives under `ServerStorage.RoleplayOSAssets.Vehicles`.

```
Vehicles/
  Civilian/
    Starter/      Compact, Hatchback, ...
    Premium/      PremiumSaloon, ...
  Services/
    Ambulance/    AmbulanceResponse, ...
    Fire/         FireEngine, ...
    Police/
      Frontline/      PoliceResponse, ...
      ArmedResponse/  ArmedResponseSUV, ...
      RoadsPolicing/  RoadsPolicingEstate, ...
```

The folder decides everything structural:

| Folder | Becomes |
| --- | --- |
| `Civilian/<Tier>/` | A civilian vehicle in that tier, sold on any forecourt covering `Civilian` |
| `Services/<Department>/` | A service vehicle for that department |
| `Services/<Department>/<Division>/` | A service vehicle for that department and division |

A department folder name must match a department id in the configuration, since
that is what ties the vehicle to the team allowed to drive it.

## Changing a vehicle's details

Anything that differs from the defaults is an **attribute on the model**, set in
Studio's Properties panel next to the car itself.

| Attribute | Type | Meaning |
| --- | --- | --- |
| `Price` | number | What it costs. Defaults to `VehicleCatalogue.DefaultPrice`. |
| `Colours` | string | Comma separated, first is the default. `"Black, Silver, White"` |
| `GamepassId` | number | Locks it behind a pass. Still shown in the showroom, offering the purchase. |
| `DisplayName` | string | Overrides the name derived from the model name. |
| `RoleIds` | string | Comma separated. Restricts a service vehicle to those roles. |
| `Starter` | boolean | Granted to a new character. |

The displayed name is derived from the model name when `DisplayName` is absent,
so `PoliceResponse` reads as "Police response". Name models the way you would
want them to read.

> A model with no `Price` costs `DefaultPrice`, which is set deliberately high.
> A car that silently costs nothing is worse than one priced wrongly, because
> nobody reports it.

## Which forecourt sells what

A dealership names the folders it sells from rather than the cars:

```lua
CityMotors = {
    Id = "CityMotors",
    Name = "City Motors",
    IncludePaths = { { "Civilian" } },
    VehicleIds = {},
},
```

`IncludePaths` is a list of folder prefixes below `Vehicles`. `{ "Civilian" }`
covers every tier under it; `{ "Civilian", "Premium" }` covers only that tier.

`VehicleIds` still works and is **additive**, for a car sold somewhere its folder
would not otherwise put it. A car matching both appears once.

The showroom and the purchase check use the same rule, so anything visible on a
forecourt can be bought there.

## Hand written entries still win

A vehicle with an explicit entry in `Config.Vehicles` keeps it. Discovery only
fills in what nobody has spoken for, so vehicles tuned by hand are never
silently replaced by folder defaults.

Discovered entries carry `Discovered = true`, which is how the two are told
apart.

## When a car does not appear

Discovery runs once at server start and logs how many it found. Check the server
log for `Vehicle catalogue built from folders`.

- **Nothing discovered at all** — the folder is missing. It must be exactly
  `ServerStorage.RoleplayOSAssets.Vehicles`.
- **One car missing** — it is probably not a `Model`. Only models are treated as
  vehicles; folders are walked through.
- **In the wrong section** — check which folder it is actually in. The path is
  the only thing that decides this.
