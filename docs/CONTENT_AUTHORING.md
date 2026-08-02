# RoleplayOS content authoring

Vehicle and Tool authoring is folder-first. Put an inert template in the correct folder; the server discovers it before vehicle, dealership and loadout services start. Runtime scripts, remotes, bindables, prompts and click detectors are rejected inside templates.

## Civilian vehicle pricing

Select the vehicle `Model` in Studio and add attributes through the Properties window.

| Attribute | Type | Required | Purpose |
|---|---|---:|---|
| `Price` | Number | Standard/Premium | Purchase price in the configured game currency. Must be zero or greater. |
| `DisplayName` | String | No | Name shown in dealership and garage interfaces. Defaults to model name. |
| `DefaultColour` | String | No | Initial colour identifier. Defaults to `Default`. |
| `DealershipId` | String | No | Dealership catalogue receiving the vehicle. Defaults to `CityMotors`. |
| `GamepassId` | Number | No | Requires this gamepass before purchase/spawn. |
| `RoleplayOSAssetId` | String | No | Stable ID when it must differ from the model name. |

Example standard vehicle:

```text
Vehicles/Civilian/Standard/Hatchback
  Price = 25000
  DisplayName = "City Hatchback"
  DefaultColour = "Blue"
  DealershipId = "CityMotors"
```

Example premium vehicle:

```text
Vehicles/Civilian/Premium/ExecutiveSaloon
  Price = 45000
  GamepassId = 123456789
  DisplayName = "Executive Saloon"
```

## Vehicle folders

```text
ServerStorage/RoleplayOSAssets/Vehicles
├── Civilian
│   ├── Starter
│   ├── Standard
│   └── Premium
└── Services
    ├── Police
    │   ├── Shared
    │   ├── Frontline
    │   ├── ArmedResponse
    │   └── RoadsPolicing
    ├── Ambulance
    ├── Fire
    ├── Control
    ├── Transport
    ├── Highways
    └── Prison
```

The direct content item must be a `Model` containing a `VehicleSeat`. Service folder placement determines department, team and eligible roles automatically. A configured manifest entry with the same ID remains authoritative and must point to the same folder.

## Tool folders

Tools mirror the service hierarchy. A Tool in `Tools/Shared` is eligible for every service loadout. A Tool in a department or police-division folder is added only to matching loadouts. Set `AutoEquip = false` when it should be registered but supplied through a locker or another workflow.

- A Tool with `RequiresHandle = true` must contain `Handle`.
- Tool name is the default stable ID; `RoleplayOSAssetId` can override it.
- `Tools/Civilian` registers civilian Tools without assigning them to service loadouts.

## World objects

Folder placement does not configure world interaction points. Use CollectionService tags and stable attributes:

- `RoleplayOSVehicleTerminal` with `TerminalId` and optional `DealershipId`.
- `RoleplayOSVehicleSpawn` with the matching `TerminalId`.
- `RoleplayOSDispatchSeat` on the actual dispatch `Seat`.
- `RoleplayOSCCTV` with `CameraId` and `DisplayName`.
- `RoleplayOSANPRSensor` on an invisible server-owned detection volume.
- `RoleplayOSSpeedCamera`, `RoleplayOSAverageSpeedEntry`, or `RoleplayOSAverageSpeedExit` on invisible detection volumes, not imported artwork.

Run the content audit after every import. Missing configured content is reported clearly; unsafe, duplicate or structurally invalid content aborts startup.
