# RoleplayOS project structure

This is the canonical map for maintaining Emergency Response: Portsmouth. Routine
changes should be made in the numbered `EDIT_HERE` modules or by inserting content
into the matching `server-assets` folder. Framework modules should not need renaming
or moving during ordinary game administration.

```text
RoleplayOS
├── src
│   ├── shared
│   │   ├── Config
│   │   │   ├── Config.luau             framework defaults and catalogue
│   │   │   └── EDIT_HERE
│   │   │       ├── 00_READ_ME.luau     editing instructions
│   │   │       ├── 01_Deployment.luau  environment, branding and integrations
│   │   │       ├── 02_Groups.luau      Roblox community IDs and ranks
│   │   │       ├── 03_Gamepasses.luau  production experience pass IDs
│   │   │       ├── 04_Uniforms.luau    clothing template IDs
│   │   │       └── 05_Balancing.luau   player-facing balance values
│   │   ├── Types                       shared type declarations
│   │   └── Utility                     pure validators and policies
│   ├── server
│   │   ├── Bootstrap.server.luau       ordered composition root
│   │   ├── Services                    authoritative gameplay domains
│   │   └── Systems                     networking and lifecycle infrastructure
│   └── client
│       ├── init.client.luau             ordered client composition root
│       ├── Controllers                 feature/input controllers
│       └── UI                          reusable interface modules
├── server-assets
│   ├── Vehicles                        inert canonical vehicle templates
│   ├── Tools                           inert canonical Tool templates
│   ├── PropertyInteriors               property interior templates
│   └── AuthoringTemplates              safe examples for builders
├── scripts                             validators and one-time Studio installers
├── tests                               source and Studio acceptance tests
└── docs                                subsystem and authoring documentation
```

## Naming rules

- Services use `<Domain>Service.luau`; client modules use `<Feature>Controller.luau`.
- Stable IDs in configuration and attributes use PascalCase without spaces.
- Player-facing names may contain spaces and belong in `DisplayName` or `Name` fields.
- Vehicle and Tool template names must match their configured stable ID unless they
  carry an explicit `RoleplayOSAssetId` attribute.
- Do not append `New`, `Final`, `Fixed`, version numbers or creator names to active
  framework files. Git is the version history.

## Safe editing boundary

Rojo's real-baseplate project owns only the four RoleplayOS roots documented in
`REAL_BASEPLATE_DEPLOYMENT.md`. It deliberately does not own Workspace, Terrain,
Lighting or Teams. Never broaden that mapping merely to make an object appear in
Studio; location-bound objects remain in the place and connect through stable tags
and attributes.

Before moving or renaming a framework file, search all `require` calls and the two
composition roots, update the relevant subsystem documentation, and run the complete
release gate. Content folders and stable IDs are persistent contracts: changing one
without a data migration can make an owned vehicle, Tool or role appear missing.

## Imported vehicle boundary

Imported vehicles may retain their driving chassis while being prepared in Workspace,
but competing ELS, siren panels, payroll scripts, remotes and unauthorised sounds must
not ship. The one-time `quarantine-legacy-vehicle-controls.studio.luau` utility moves
the known broken controls to `ServerStorage/RoleplayOSLegacyVehicleQuarantine` rather
than deleting them. This keeps rollback possible while preventing the scripts from
running. The quarantine is not a production asset source and should be removed only
after the cleaned vehicles have passed driving and RoleplayOS ELS acceptance.
