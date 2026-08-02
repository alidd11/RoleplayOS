ROLEPLAYOS CONTENT — PLACE ASSETS IN THESE FOLDERS

Vehicles/Civilian/Starter
  Starter vehicles. Model must contain a VehicleSeat.

Vehicles/Civilian/Standard
  Normal dealership vehicles. Add numeric Price attribute (for example 25000).

Vehicles/Civilian/Premium
  Premium vehicles. Add numeric Price and optional numeric GamepassId attributes.

Vehicles/Services/Police/Shared
  Vehicles available across police roles.

Vehicles/Services/Police/Frontline
  Frontline Policing vehicles.

Vehicles/Services/Police/ArmedResponse
  Armed Response vehicles.

Vehicles/Services/Police/RoadsPolicing
  Roads Policing vehicles.

Vehicles/Services/Ambulance, Fire, Control, Transport, Highways, Prison
  Vehicles for each respective service.

Tools/Shared
  Shared service tools.

Tools/Services/<Department> and Tools/Services/Police/<Division>
  Department/division loadout tools. Set AutoEquip=false for locker-only tools.

Tools/Civilian
  Civilian tools that are not automatically added to service loadouts.

Optional vehicle attributes:
  DisplayName (String), DefaultColour (String), DealershipId (String),
  GamepassId (Number), RoleplayOSAssetId (String).

Never insert scripts, remotes, bindables, prompts or click detectors into templates.
RoleplayOS validates and rejects unsafe content at startup.

Full guide: docs/CONTENT_AUTHORING.md in the RoleplayOS repository.
