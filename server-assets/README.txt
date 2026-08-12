ROLEPLAYOS CONTENT — PLACE ASSETS IN THESE FOLDERS

PRICING
  For a new civilian vehicle, select its top-level Model and add a Number
  attribute named Price. Example: Price = 25000. Standard and Premium vehicles
  require Price >= 0. Starter vehicles may be free.

  A vehicle already declared in src/shared/Config/Config.luau uses the Price in
  that declaration. Do not try to override a configured vehicle with an
  attribute. The server chooses and charges the price; clients never supply it.

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

Public employment fleets still live with the service that issues them. For
example, the TaxiDriver job uses Vehicles/Services/Transport/CorollaTaxi and
the shared TransportFleet spawner; it does not need a second TaxiFleet folder.

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

PRODUCTION CERTIFICATION (required for every inserted Model/Tool)
  RoleplayOSAssetCertified = true
  RoleplayOSReviewVersion = 1
  RoleplayOSAssetSource = creator/source/licence or "Universal Projects original"
  RoleplayOSRealWorldReference = specific UK object/reference set
  RoleplayOSReviewedBy = internal reviewer or review ticket

Do not certify an asset merely because it looks plausible. Inspect all views, scale,
orientation, grip/seat/pivot, collision, hidden geometry, markings, provenance,
performance budgets and device behaviour. The server rejects uncertified content.

Full guide: docs/CONTENT_AUTHORING.md in the RoleplayOS repository.
