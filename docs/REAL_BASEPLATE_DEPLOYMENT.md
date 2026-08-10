# Real baseplate deployment

This procedure installs RoleplayOS into an existing Roblox place without making Rojo the owner of the map. The map, Terrain, Lighting, Teams and all unrelated Studio instances remain owned by the place file.

Never connect the production place to `default.project.json` as the first migration step. Use `real-baseplate.project.json`; it deliberately omits `Workspace` and `Teams` and preserves unknown instances in every service it touches.

## What is installed

```text
ReplicatedStorage
└── RoleplayOS                 source-controlled shared modules and configuration

ServerScriptService
└── RoleplayOS                 source-controlled server runtime

ServerStorage
└── RoleplayOSAssets           canonical vehicles, tools and interiors

StarterPlayer
└── StarterPlayerScripts
    └── RoleplayOSClient       source-controlled client runtime
```

RoleplayOS does not manage `Workspace`, `Terrain`, `Lighting`, `Teams`, `StarterGui`, `StarterPack` or existing systems elsewhere in the place.

## Mandatory backup and staging workflow

1. In Creator Dashboard, create a private staging place inside the **Emergency Response: Portsmouth** experience. Do not test the first migration in the live start place.
2. Open the real baseplate and use **File → Save to File** to create a dated `.rbxl` or `.rbxlx` backup.
3. Publish a separate dated backup place/version. Record its place version number and the current Git commit.
4. Copy the real baseplate into the private staging place. Confirm that Terrain, map models, Teams, Lighting and existing scripts are present before connecting Rojo.
5. Stop Play mode. Never connect Rojo while a simulation is running.
6. Run the local deployment guard:

   ```sh
   python3 scripts/validate-deployment.py
   rojo build real-baseplate.project.json --output build/RoleplayOSRealBaseplate.rbxlx
   ```

7. Start `rojo serve real-baseplate.project.json`, connect the Studio plugin to the **staging place**, and inspect the proposed changes before accepting them.
8. Confirm that the only new or updated roots are the four RoleplayOS containers shown above. If the plugin proposes removing Workspace, Teams, Terrain or unrelated instances, disconnect immediately.
9. Save and publish the staging place only after the smoke tests below pass.
10. Repeat the same connection against the live place during a maintenance window. Use the exact Git commit tested in staging.

## Canonical asset migration

Gameplay models must not remain loose in Workspace or in an ad-hoc ServerStorage folder. Keep one clean, script-free canonical model under `ServerStorage/RoleplayOSAssets`; spawners clone from there.

The production Rojo project deliberately does not manage `Workspace` or `Teams`—including
their service properties. Configure streaming and team objects in the authorised Studio
place, then preserve them during every RoleplayOS sync.

```text
RoleplayOSAssets
├── Vehicles
│   ├── Civilian/Starter
│   ├── Civilian/Standard
│   ├── Civilian/Premium
│   └── Services/{Police,Ambulance,Fire,Control,Transport,Highways,Prison}
├── Tools
│   ├── Shared
│   ├── Civilian
│   └── Services/{Police,Ambulance,Fire,Control,Transport,Highways,Prison}
├── PropertyInteriors
└── AuthoringTemplates
```

For each existing vehicle or tool:

1. Duplicate it in a quarantined local place and remove all `Script`, `LocalScript`, `ModuleScript`, remotes, bindables, prompts and click detectors supplied by the model author.
2. Retain only geometry, attachments, constraints, animations, sounds and textures that are licensed and actually required.
3. Give the model a stable, configuration-facing name. Do not use a display name as its identity.
4. Export the sanitised model as an `.rbxm` and store it at its canonical path under `server-assets`. A model file can replace a `.gitkeep`; do not keep a second Studio-only master.
5. Add or update the corresponding `AssetPath` in `Config.luau`.
6. Run the structure/build checks, sync to staging and let `ContentValidationService` report missing or malformed content.

Folders describe where an asset belongs; they do not grant permission. Roles, group ranks, gamepasses and server kind remain server-authoritative configuration.

### Required vehicle contract

- Root is a `Model` with a stable `RoleplayOSAssetId` string attribute.
- A usable `VehicleSeat` exists.
- A primary/chassis part is defined and the assembly is welded or constrained correctly.
- Registration display parts use one of the configured plate names.
- Workspace vehicle-name fallbacks are development-only. Production spawns only reviewed templates beneath `ServerStorage > RoleplayOSAssets`.
- The model contains no networking, DataStore calls or executable scripts.
- The configured `AssetPath`, department and division agree with the folder.

### Required tool contract

- Root is a `Tool` with a stable `RoleplayOSAssetId` string attribute.
- A `Handle` exists unless `RequiresHandle` is deliberately disabled.
- The tool contains presentation assets only. Trusted behaviour stays in RoleplayOS services/controllers.
- The configured `AssetPath`, department and loadout agree with the folder.

## Map integration: tags and attributes

Map objects stay in Workspace and are discovered through `CollectionService` tags. Tags are preferable to scripts inside map models.

| Object | Required tag | Important attributes |
|---|---|---|
| Team/player spawn | `RoleplayOSSpawnPad` | `SpawnId` matching `Config.Spawns`; Team name must match exactly |
| Vehicle terminal | `RoleplayOSVehicleTerminal` | stable terminal/dealership identifier |
| Vehicle bay | `RoleplayOSVehicleSpawn` | terminal/dealership identifier; unobstructed spawn volume |
| CCTV camera/viewpoint | `RoleplayOSCCTV` | stable `CameraId`, player-facing `DisplayName` |
| ANPR sensor | `RoleplayOSANPR` | stable sensor/site identifier |
| Fixed speed camera | `RoleplayOSSpeedCamera` | speed limit and stable camera/site identifier |
| Average-speed entry | `RoleplayOSAverageSpeedEntry` | matching corridor identifier and speed limit |
| Average-speed exit | `RoleplayOSAverageSpeedExit` | matching corridor identifier and speed limit |
| Custody booking point | `RoleplayOSCustodyDesk` | stable station/desk identifier |
| Custody cell spawn | `RoleplayOSCustodyCellSpawn` | optional stable `CellId`; tag a safe anchored part or `SpawnLocation` inside a cell |
| Detainee vehicle seat | `RoleplayOSCustodySeat` | tag only the rear seat(s) authorised for detainee transport |
| Dispatch seat | configured dispatch-seat tag | stable control-room identifier; do not classify solely from `VehicleSeat` |
| Minimap bounds | `RoleplayOSMinimapBounds` | map bounds geometry |
| Minimap road | `RoleplayOSMinimapRoad` | road classification where required |
| Minimap point | `RoleplayOSMinimapPOI` | name/icon/category attributes used by the controller |

Keep invisible trigger parts anchored, non-collidable and as simple as possible. A visual camera, sign or desk may be a detailed model, but the tagged trigger/viewpoint should be a small trusted part owned by the map team.

## Production configuration gate

Before publishing staging, make a reviewed production configuration change and run:

```sh
python3 scripts/validate-deployment.py --production
```

The gate requires or highlights:

- `Framework.Environment = "Production"`;
- Studio mock data and mock emergency access disabled;
- final Roblox group links and minimum ranks; Control intentionally uses the main Universal Projects group;
- all live gamepass IDs checked against this experience;
- final uniform template IDs;
- published API/DataStore access enabled only in the private staging place first;
- DataStore names and schema version reviewed before live traffic;
- experience access behaviour tested with an authorised and unauthorised account;
- StreamingEnabled behaviour tested around all tagged world integrations.

Do not commit API keys, cookies or Creator Dashboard credentials. RoleplayOS does not need them in source.

## Staging smoke tests

Test with at least two Roblox accounts in a private published server, not only Studio mock mode:

1. Authorised group member joins; unauthorised member receives the intended access response.
2. Civilian character creation, respawn and correct spawn location work.
3. Frontline, Armed Response and Roads Policing access matches real group ranks/gamepasses.
4. Every service team receives only its configured tools and vehicles.
5. Vehicle purchase/spawn, stable registration, leave/rejoin and second-server registration uniqueness work.
6. Dispatcher seat opens Dispatch rather than vehicle UI; calls and unit assignment stay server-local.
7. MDT, custody, warrants and ANPR permissions and persistence work across rejoin.
8. CCTV and speed/average-speed sensors work after streaming out and back in.
9. Phone, stamina, hunger, ID card and compact vehicle HUD do not overlap Roblox CoreGui on desktop, mobile or controller.
10. Server and client consoles remain free of errors during join, respawn, team change, vehicle use and shutdown.

Use a fresh staging DataStore namespace for destructive test data. Never point experimental schema changes at the live namespace.

## Release and rollback

Record the approved Git commit, staging place version, live place version and configuration review before release.

If the live smoke test fails:

1. Shut down live servers from Creator Dashboard if player data integrity is at risk.
2. Restore the recorded previous place version or publish the dated `.rbxl` backup.
3. Redeploy the last known-good Git commit with `real-baseplate.project.json`.
4. Do not roll a DataStore schema backwards blindly. Keep forward-compatible readers or deploy a reviewed corrective migration.
5. Preserve logs and the failed version for diagnosis; do not attempt repairs directly in the only live copy.

Disconnecting Rojo alone does not roll back scripts already saved or published. Place-version restore plus the last known-good Git commit is the reliable rollback pair.
