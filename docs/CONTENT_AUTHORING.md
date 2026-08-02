# RoleplayOS content authoring

Vehicle and Tool authoring is folder-first. Put an inert template in the correct folder; the server discovers it before vehicle, dealership and loadout services start. Runtime scripts, remotes, bindables, prompts and click detectors are rejected inside templates.

## Production asset certification

RoleplayOS deliberately distinguishes functional staging fallbacks from production-quality models. Every inserted vehicle or Tool template must pass a human visual review and carry all of these attributes on its top-level `Model` or `Tool`; otherwise `ContentValidationService` aborts startup.

| Attribute | Type | Requirement |
|---|---|---|
| `RoleplayOSAssetCertified` | Boolean | `true` only after the checklist below is complete. |
| `RoleplayOSReviewVersion` | Number | Must equal `Config.ContentQuality.CertificationVersion`. |
| `RoleplayOSAssetSource` | String | Creator/source and licence or “Universal Projects original”. Never claim ownership of an imported asset. |
| `RoleplayOSRealWorldReference` | String | The specific UK object/vehicle/reference set used for proportions, markings and operation. |
| `RoleplayOSReviewedBy` | String | Internal reviewer or review ticket identifier. |
| `RoleplayOSAssetId` | String | Stable unique identity. Required for world assets and recommended for every template. |
| `RoleplayOSReplacesAssetId` | String | Set only on a replacement; startup rejects the replacement while the obsolete asset ID still exists. |

Certification means all of the following have been checked:

1. The model has been compared from front, rear, both sides and three-quarter views against reliable UK references; silhouette, scale, mounting and functional parts match the intended object.
2. Branding, badges, registrations and markings are original/licensed or fictionalised. A real decal is not automatically safe to reuse.
3. Every imported script, remote, bindable, prompt and click detector has been removed. RoleplayOS supplies all behaviour.
4. The model is correctly oriented, has intentional collision/query/touch properties, no loose parts, no hidden geometry and an appropriate pivot/driver seat/Tool grip.
5. Part and descendant budgets in `Config.ContentQuality` pass. Texture resolution and mesh complexity are proportionate to the object’s screen size.
6. The asset has been inspected in desktop, phone, gamepad and relevant vehicle/VR contexts before certification.

Setting attributes without performing the review is not certification. Generated primitive cuffs are marked `RoleplayOSBuiltInFallback`; they keep staging functional but are not evidence that the final realistic cuff model is complete.

## Civilian vehicle pricing

Select the vehicle `Model` in Studio and add attributes through the Properties window.

For a newly discovered vehicle, the `Price` attribute is its authoritative server-side dealership price. A vehicle already declared in `src/shared/Config/Config.luau` instead uses the `Price` in that declaration; registered configuration entries take precedence over Model attributes. Use one source of truth per vehicle.

| Attribute | Type | Required | Purpose |
|---|---|---:|---|
| `Price` | Number | Standard/Premium | Purchase price in the configured game currency. Must be zero or greater. |
| `DisplayName` | String | No | Name shown in dealership and garage interfaces. Defaults to model name. |
| `DefaultColour` | String | No | Initial colour identifier. Defaults to `Default`. |
| `DealershipId` | String | No | Dealership catalogue receiving the vehicle. Defaults to `CityMotors`. |
| `GamepassId` | Number | No | Requires this gamepass before purchase/spawn. |
| `RoleplayOSAssetId` | String | No | Stable ID when it must differ from the model name. |

The player never sends a price. The purchase request contains the stable vehicle ID; `DealershipService` resolves the price on the server, debits the selected character, creates the persistent ownership record, and issues an automatic refund if record creation fails.

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

Visible world artwork is certified separately from invisible functional sensors. Put the
`RoleplayOSWorldAsset` tag on the top-level visible `Model` and set
`RoleplayOSAssetKind` to one of the configured required kinds. The model must carry the
same source, reference, reviewer, certification-version and certification attributes as
vehicle and Tool templates. Imported scripts and interaction objects remain forbidden.

Every visible world model must be a direct child of its kind folder:

```text
Workspace/RoleplayOSWorldAssets
├── ANPRCamera
├── CCTVCamera
├── CustodyFurniture
├── DealershipNPC
├── DispatchFurniture
└── SpeedCamera
```

For example, an ANPR camera with `RoleplayOSAssetKind = "ANPRCamera"` must be directly
inside `Workspace/RoleplayOSWorldAssets/ANPRCamera`. A tagged model elsewhere is rejected.

Do not tag invisible trigger volumes as visual assets. Keep the functional tag on the
invisible volume and the certification tag on its visible shell. A replacement is complete
only after the old shell has been removed, the new shell is in the correct world folder,
and the certification ledger in `docs/WORLD_ASSET_CERTIFICATION.md` has been updated.

Quarantine is temporary. Development reports any descendants under
`RoleplayOSAssetQuarantine`; Production refuses to start until the quarantine is empty or
deleted. When a new root uses `RoleplayOSReplacesAssetId`, the old stable ID must no longer
exist anywhere in registered content.

Folder placement does not configure world interaction points. Use CollectionService tags and stable attributes:

- `RoleplayOSVehicleTerminal` with `TerminalId` and optional `DealershipId`.
- `RoleplayOSVehicleSpawn` with the matching `TerminalId`.
- `RoleplayOSDispatchSeat` on the actual dispatch `Seat`.
- `RoleplayOSCCTV` with `CameraId` and `DisplayName`.
- `RoleplayOSANPRSensor` on an invisible server-owned detection volume.
- `RoleplayOSSpeedCamera`, `RoleplayOSAverageSpeedEntry`, or `RoleplayOSAverageSpeedExit` on invisible detection volumes, not imported artwork.

Run the content audit after every import. Missing configured content is reported clearly; unsafe, duplicate or structurally invalid content aborts startup.
