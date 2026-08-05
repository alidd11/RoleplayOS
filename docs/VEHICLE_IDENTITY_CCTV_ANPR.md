# Vehicle identity, CCTV and ANPR

Every purchased vehicle receives one generated registration when its persistent ownership record is created. The registration is stored with that exact vehicle, so later garage or dealership spawns reuse it. Team vehicles use a persistent key made from the player, team and vehicle definition, giving that player the same registration whenever they respawn the same team vehicle.

Spawned models carry server-authored vehicle, registration and owner attributes. Existing parts named `RegistrationPlate`, `NumberPlate`, `LicencePlate` or `LicensePlate` receive the plate display. If a model has none, RoleplayOS adds lightweight welded front and rear plates.

The Custom Registration Plate pass is `1937140343`. Civilians can use the compact **Custom Plate** interface to select an owned vehicle and submit a 2–8 character value. Custom values are upper-cased, restricted to letters, numbers and spaces, length-limited, filtered with Roblox `TextService`, rejected if filtering changes the value, atomically reserved in a dedicated DataStore and audited. The reservation prevents two live servers from accepting the same custom plate. The server also checks pass entitlement and ownership; clients cannot assign a registration directly.

Tag the lens or view-origin `BasePart` of a CCTV model with `RoleplayOSCCTV`. Set `CameraId` to a stable unique ID and `DisplayName` to the control-room label. Control duty can request the bounded server camera list and use the dispatch console's **View CCTV** action. The client receives serialised positions rather than Instances and exits back to the normal Roblox camera.

Tag an invisible road detection volume with `RoleplayOSANPR`. Optional attributes are `Location` and the linked `CameraId`. The server accepts only vehicles carrying a server-authored RoleplayOS registration, applies a sensor/registration cooldown, resolves the persistent vehicle owner and checks active warrants. A positive hit creates an immediate ANPR dispatch call and sends the popup only to players currently on the `RoadsPolicingOfficer` role. Every hit is audited.

Keep sensors simple and localised. `Touched` connections are created only for tagged sensors and capped by configuration; no global per-frame vehicle scan is used.
