# RoleplayOS UK environment modelling bible

This document is a production guide for replacing the current CCTV, ANPR, speed-enforcement, control-room and custody blockouts. Dimensions labelled **game target** are art-direction estimates, not statutory or manufacturer dimensions. Model to the silhouette and installation logic, not to a copied branded product.

## Global scale and construction rules

- Treat 1 Roblox stud as approximately 0.28 m for environment authoring, then verify every interaction against an R15 avatar.
- Use real-world-sized doors (roughly 7.2–7.8 studs high), desk worktops (roughly 2.6–2.9 studs high), and roadside columns (roughly 14–30 studs high depending on installation).
- Put visual meshes in a non-colliding `Visual` folder. Use a few invisible primitive colliders in `Collision`.
- Keep interaction and detection geometry separate from artwork in `Anchors`. Replacing art must never move a speed sensor, camera viewpoint, custody prompt, seat or dispatch interaction.
- Pivots belong at the mounting interface: pole base, wall plate, desk floor contact, or cell-door hinge.
- Avoid unions for production assets. Prefer MeshParts for manufactured housings and Parts for poles, cabinets, desks and collision.
- Use subtle roughness and edge bevels. UK roadside equipment is weathered powder-coated or galvanised metal, not glossy plastic.
- Never leave third-party scripts, remotes, prompts, click detectors or constraints in imported reference models.

## Asset budgets

| Asset | Hero triangles | Mid LOD | Far representation | Texture budget |
|---|---:|---:|---|---|
| Small fixed camera or ANPR head | 2,500 | 800 | 1–3 primitives | one 512 atlas |
| PTZ CCTV head and bracket | 3,500 | 1,200 | 2–4 primitives | one 512 atlas |
| Gatso-style cabinet and post | 4,000 | 1,200 | 2–5 primitives | one 512 atlas |
| Complete roadside camera site | 7,500 | 2,500 | simplified pole/sign silhouette | one 1024 shared atlas |
| Dispatch workstation | 6,000 | 2,000 | desk and dark monitor cards | one 1024 shared room atlas |
| Booking position | 8,000 | 3,000 | counter silhouette | one 1024 shared room atlas |
| Custody cell shell and fittings | 8,000 | 3,000 | room portal/occluder | one 1024 shared suite atlas |

Use `RenderFidelity = Automatic` unless a silhouette visibly collapses. Disable shadows on tiny lenses, bolts, labels and cables. Switch off decorative monitor surfaces and camera status lights beyond about 120 studs. Stream custody wings and control-room interiors as separate models.

## 1. Town-centre CCTV

### Authentic forms

Build three variants:

1. **Pendant PTZ dome** — an off-white cylindrical upper housing with a dark hemispherical lower dome, short pendant neck and swan-neck wall or pole bracket. A current outdoor Axis Q60-class unit is about 232 mm diameter by 271 mm high, useful as a reliable scale reference.
2. **Fixed bullet camera** — rectangular or cylindrical off-white body, small sunshield, black lens window, adjustable knuckle and compact junction box.
3. **Multi-sensor pole** — one PTZ dome below a pole cap with one or two fixed overview cameras, weatherproof junction cabinet and black cable loops.

### Game targets

- PTZ head: 0.8–0.9 stud diameter, 0.9–1.1 stud high.
- Wall projection including arm: 2.0–3.5 studs.
- Pole installation: 18–28 studs high; avoid mounting where foliage blocks the intended view.
- Palette: warm off-white powder coat, dark smoke dome, galvanised bracket, black UV cable and small red/green service LED.
- Add grime under seams and at the lower edge, but no heavy rust on modern housings.

### Interaction anchors

- `ViewAnchor`: Attachment at the optical centre, oriented along the true viewing direction.
- `MountAnchor`: Attachment at bracket/pole connection.
- `ServiceAnchor`: optional prompt location at the pole cabinet, never on the camera head.
- `CameraId`: stable attribute on the trusted root model.

The visible dome may rotate cosmetically, but the server-approved camera list and permissions remain authoritative. The government surveillance code treats CCTV and ANPR as complete systems, including storage and processing—not merely visible camera heads—so the dispatch UX should also communicate camera identity, purpose and availability.

**References:** [Axis Q6078-E manufacturer datasheet](https://www.axis.com/dam/public/ee/e8/e4/datasheet-axis-q6078-e-ptz-camera-en-US-412002.pdf); [UK Surveillance Camera Code of Practice](https://www.gov.uk/government/publications/update-to-surveillance-camera-code/amended-surveillance-camera-code-of-practice-accessible-version).

## 2. Police and roadside ANPR

### Authentic forms

Use a compact integrated camera rather than a domestic CCTV camera. The characteristic arrangement is:

- dark rectangular optical window or lens barrel;
- adjacent infrared illuminator panel or a second matching head;
- weatherproof grey/off-white enclosure with a modest sunshield;
- rigid pole, gantry, bridge-parapet or roadside cabinet installation;
- narrow view aimed at the number-plate capture zone, not a broad scenic view.

Jenoptik describes VECTOR as an integrated ANPR platform and its P2P system as capable of monitoring as many as four lanes with day/night infrared capture. Model one head per plausible lane group rather than placing a camera over every lane automatically.

### Game targets

- Main head: approximately 1.2–1.8 studs long, 0.55–0.8 stud wide, 0.55–0.8 stud high.
- IR head/panel: 0.5–0.8 stud square or a second housing beside the camera.
- Cantilever arm: 4–10 studs depending on verge setback.
- Equipment cabinet: 1.5–2.2 studs wide, 1.0–1.5 studs deep, 3–4.5 studs high on a concrete plinth.
- Use charcoal optical glass, satin grey or yellow housing, galvanised supports and black conduit.

### Interaction anchors

- `CaptureAnchor`: points at the centre of the lane capture zone.
- `DetectionZone`: invisible, server-owned volume separate from imported art.
- `RoadDirection`: attribute or Attachment orientation.
- `CameraId`, `SiteId`, `LaneGroup`, `DisplayName`: stable metadata.

Do not make ANPR physically emit a visible ray. A restrained IR emitter glow is acceptable only at very close range. Dispatch should receive an event after a trusted server-side plate/wanted lookup, never from a client camera script.

**References:** [Jenoptik UK history and VECTOR platform](https://www.jenoptik.co.uk/); [National ANPR standards for policing and law enforcement](https://www.gov.uk/government/publications/national-anpr-standards/national-anpr-standards-for-policing-and-law-enforcement-accessible-version).

## 3. SPECS / average-speed installations

### Authentic forms

Build the modern compact P2P family first:

- paired sites at the beginning and end of an enforced section;
- compact rectangular camera head with integrated or adjacent IR illumination;
- roadside pole, bridge, tunnel wall or temporary roadworks support;
- yellow, grey or mixed roadside equipment depending on the chosen scheme;
- visible camera-warning signing on the approach.

Average speed is derived from plate captures and timestamps at separated points. The model must therefore read as a **paired corridor**, not a single flash camera. Jenoptik states that VECTOR P2P can be stationary or semi-stationary, monitor up to four lanes, work bidirectionally and capture front or rear views depending on positioning.

### Roblox setup

- Give entry and exit art different stable IDs but the same `CorridorId`.
- Put detection volumes across the carriageway, not inside the visual camera head.
- Add a small roadside cabinet and believable cable route at permanent sites.
- For temporary roadworks, use weighted bases or temporary columns, barrier protection and a less permanent conduit treatment.
- Use `RoleplayOSAverageSpeedEntry` and `RoleplayOSAverageSpeedExit` only on trusted detection volumes.

**Reference:** [Jenoptik average-speed and VECTOR P2P product information](https://www.jenoptik.com/products/road-safety/average-speed-camera).

## 4. Gatso-style fixed spot-speed camera

### Authentic form

For a recognisable legacy UK roadside silhouette, use:

- tall rectangular yellow enforcement cabinet;
- flat or gently sloped top cap;
- dark horizontal or square camera/flash apertures on the road-facing side;
- sturdy short post or pedestal on a concrete pad;
- separate grey/yellow equipment cabinet where appropriate;
- rear access panel seams, locks and small warning labels.

Do not brand it as a specific commercial product unless licensed. Make a generic UK fixed-camera cabinet informed by the family silhouette. Sensys Gatso remains the relevant manufacturer lineage, but photographs, logos and exact industrial designs should be treated as reference, not copied decals.

### Game targets

- Cabinet: 1.4–1.8 studs wide, 1.0–1.4 studs deep, 3.5–5 studs high.
- Total lens height: roughly 7–11 studs above road surface depending on site.
- Yellow paint should be slightly orange and satin, with darker dirt at the base and panel seams.
- Use separate glass/flash materials; do not represent the face with text labels.
- One short flash is enough for presentation; rate-limit it and do not light the entire street.

Place the trusted fixed-speed detection volume so it matches the lane and camera aim. The DfT says fixed camera and relevant signs should normally be visible in the same driver view where practicable.

**References:** [Sensys Gatso portable and speed-enforcement product family](https://www.sensysgatso.com/solutions-road-safety-enforcement/speed-enforcement-equipment-systems/portable-speed-enforcement); [DfT Traffic Signs Manual, Chapter 3](https://assets.publishing.service.gov.uk/government/uploads/system/uploads/attachment_data/file/782724/traffic-signs-manual-chapter-03.pdf).

## 5. Roadside signs and decals

### Speed-camera signs

Use the prescribed UK designs rather than invented yellow warning plaques:

- Diagram 878 camera symbol with optional legend `Speed cameras`.
- Diagram 878 varied to `Average speed check` for corridor enforcement.
- Diagram 880 for a camera ahead on a lit 30 mph road.
- Diagram 880.1 for camera ahead with national speed limit on an unlit road.
- Camera symbol may be co-located with diagram 670/671 speed-limit signing as shown in the Traffic Signs Manual.

For a lit 30 mph road, the manual specifies the 300 mm camera sign size. At the project scale this is about 1.07 studs. Preserve the official symbol geometry, margins and Transport-style lettering. Use a white retroreflective face, black symbol/text, grey reverse, extruded aluminium edge and galvanised post. A yellow backing board is optional only where the chosen prescribed arrangement supports it; it must not become the default art style.

### CCTV notice

A credible notice should state:

- that CCTV/images are being monitored or recorded;
- the purpose, such as crime prevention and public safety;
- the responsible fictional operator;
- fictional contact information or an in-world information route.

Example in-game wording:

> CCTV IN OPERATION  
> Images are monitored and recorded for crime prevention and public safety.  
> Controlled by Portsmouth Community Safety Partnership.  
> Information: roleplayos.local/cctv

Do not use a real council, police-force crest, telephone number or web address. The ICO says signs should be visible before people enter the monitored area and sized for their audience.

### Decal production

- Recreate prescribed sign vectors from the government diagrams rather than downloading random Creator Store decals.
- Keep an editable SVG source and export a 1024 square atlas with mip-safe padding.
- Record the source diagram number and revision in asset metadata.
- Do not place manufacturer logos on camera equipment.

**References:** [DfT Traffic Signs Manual collection](https://www.gov.uk/government/publications/traffic-signs-manual); [ICO video-surveillance transparency guidance](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/cctv-and-video-surveillance/guidance-on-video-surveillance-including-cctv/how-can-we-comply-with-the-data-protection-principles-when-using-surveillance-systems/).

## 6. Police control and dispatch room

### Layout language

The room should feel like a UK force control room, not an aircraft cockpit:

- rows or shallow pods of sit/stand workstations;
- two or three monitors per operator on articulated arms;
- separate call-handler and dispatcher zones;
- supervisor positions with clear sightlines;
- restrained large wall displays for incident load, mapping and operational status;
- acoustic ceiling, carpet tile or resilient technical flooring, neutral desks and cool-white task lighting;
- cable trays, docking stations, headsets, keyboards, radios and under-desk equipment details.

Cambridgeshire Constabulary describes a Contact Centre with call handlers and a separate Force Control Room with dispatchers, supervisors and inspectors. Preserve that operational distinction in room zoning and UX.

### Workstation game targets

- Worktop: 5–7 studs wide, 2.5–3.2 studs deep, 2.6–2.9 studs high.
- Operator clearance: at least 3 studs behind chair in the gameplay route.
- Monitor: 1.8–2.4 studs wide, 1.0–1.4 studs high; shallow bezel and articulated arm.
- Three-screen arc: side screens yawed 15–25 degrees toward the user.
- Place a real `Seat` in a simple invisible chair collider; visual casters and mechanisms should not collide.

### Interaction anchors

- `OperatorSeat`: the only seat that opens dispatch, identified by a dispatch-specific tag/attribute rather than generic vehicle occupancy.
- `ScreenAnchorPrimary`, `ScreenAnchorMap`, `ScreenAnchorCCTV`.
- `SupervisorAnchor` for permissions and overview UX.
- Seat detection must explicitly exclude `VehicleSeat`; a normal dispatch chair should never trigger vehicle UI.

Screens should show restrained, readable operational UI—incident list, selected incident, available units and map—not decorative walls of tiny text.

**Reference:** [Cambridgeshire Constabulary: Inside the Control Room](https://www.cambs.police.uk/police-forces/cambridgeshire-constabulary/areas/campaigns/campaigns/inside-the-control-room/).

## 7. Custody booking area

### Layout

- Secure vehicle dock leads to holding/waiting space, then booking/charge desks, search/property processing, healthcare/interview rooms and separated cell corridors.
- The booking desk must maintain good eye contact and verbal communication between custody officer and detainee.
- Provide a waiting position where escorting officers can remain with a detainee while preserving reasonable privacy.
- Use two or more booking positions in the hero suite; each should have a computer, desk microphone/intercom detail, property tray, fingerprint/photo route and secure staff-side circulation.
- Do not create a high theatrical courtroom bench. Modern custody counters are robust operational workstations with rounded, easily cleaned surfaces.

### Game targets

- Counter segment: 6–9 studs wide; detainee-side standing datum about 3.3–3.8 studs high where visually appropriate, with accessible communication sections.
- Keep all exposed corners rounded and avoid decorative protrusions.
- Use muted blue-grey, warm grey, pale resilient wall panels, stainless details and dark durable worktops.
- Lighting: even, low-glare and robust. A specialist summary of the Home Office guide cites 350–550 lux for photo/fingerprint areas and about 350 lux for interview/medical rooms; treat these as lighting intent rather than attempting photometric simulation.

### Anchors

- `CustodyDeskAnchor`: trusted prompt/interaction position.
- `DetaineeStandAnchor` and `CustodyOfficerSeatAnchor`.
- `PhotoAnchor`, `FingerprintAnchor`, `PropertyAnchor`, `CellEscortAnchor`.
- Separate the booking UI trigger from generic seating.

**References:** [College of Policing buildings and facilities guidance](https://www.college.police.uk/app/detention-and-custody/buildings-and-facilities); [NPEG custody management and design standards](https://npeg.police.uk/our-work/custody-management/).

## 8. Custody cells and corridors

### Required visual features

- Smooth, robust, easy-clean wall and floor finishes with coved junctions.
- Integral plinth bed with a simple mattress.
- Anti-ligature sanitary fittings and flush controls.
- Robust outward-opening cell door with anti-ligature handle, food hatch, viewer and privacy cover.
- Door leaf fits tightly: College of Policing guidance states no more than 2 mm at the closed door/rebate; an IOPC update cites no more than 10 mm under the door. Represent this visually as a tight fit, without spending geometry on millimetre accuracy.
- Flush, vandal-resistant lighting and a small protected CCTV housing in designated cells.
- No loose props, exposed cables, sharp trim, conventional coat hooks or ordinary domestic furniture.

### Operational layout

Provide visibly separate cell areas for adult men, adult women, and children/young people in a full suite. The College of Policing recommends at least three separate cell blocks or areas in new designs. For the game, separation may be represented as three signed corridors sharing a central staff spine.

At least one cell should be modelled as CCTV-observed. Make signage clearly visible and legible, consistent with College guidance. Camera coverage should support the fictional custody workflow without implying a blind decorative camera.

### Roblox construction

- Each cell is a streaming/occlusion unit with one shell mesh, door assembly, bed, sanitary assembly and light.
- Use a single invisible floor/wall collision shell and a separate door collider.
- Corridor doors outside the active zone may become static shells.
- Keep operational attributes on the cell root: `CellId`, `Observed`, `BlockId`, `OccupancyState`.

**References:** [College of Policing buildings and facilities](https://www.college.police.uk/app/detention-and-custody/buildings-and-facilities); [College of Policing custody CCTV guidance](https://www.college.police.uk/app/detention-and-custody/cctv); [IOPC cell-door safety recommendation](https://www.policeconduct.gov.uk/our-work/learning/investigation-womans-injury-sustained-whilst-custody-metropolitan-police-service).

## Replacement map for current RoleplayOS blockouts

| Priority | Current blockout | Production replacement | Preserve from current system |
|---:|---|---|---|
| P0 | ANPR roadside sign/camera blocks | Compact VECTOR-style head, separate IR module, cabinet, prescribed warning sign | trusted detection zone, camera/site IDs, roads-policing alert routing |
| P0 | Average-speed camera pair | Matched P2P entry/exit sites with shared visual family and `Average speed check` signing | corridor ID, entry/exit tags, timestamp logic |
| P0 | Dispatch chair mistaken for vehicle seat | Dedicated ergonomic operator chair and workstation with dispatch-specific seat identity | dispatcher permissions and call assignment logic |
| P0 | Custody booking desk block | Two-position rounded secure booking counter with detainee/officer anchors | booking prompt/tag and persistent record workflow |
| P1 | Fixed speed camera block | Generic yellow Gatso-family cabinet, pedestal, flash/lens windows and correct approach signing | fixed-camera tag, speed limit, tolerance and fine logic |
| P1 | CCTV pole/block | Pendant PTZ hero variant plus fixed bullet and multi-sensor variants | camera IDs, display names and approved dispatch viewer list |
| P1 | Custody cell block | tight outward-opening door, hatch/viewer, plinth bed, sanitary unit and observed-cell variant | cell IDs and custody state |
| P2 | Control-room furniture | modular sit/stand desk pods, monitor arms, headsets, acoustic treatment and supervisor row | existing dispatch UX and seat activation |
| P2 | Generic warning decals | project-authored vector atlas based on DfT diagrams and ICO-compliant fictional notices | sign placement anchors |

## Acceptance checklist

- Silhouette is recognisably British at 30–50 studs without relying on text.
- Roadside equipment has a plausible mount, cabinet, cable path and capture direction.
- Average-speed cameras appear as a paired corridor.
- Signs use correct diagram families and readable scale.
- CCTV notices identify a fictional operator and purpose.
- Dispatch chairs are not `VehicleSeat` instances and do not activate vehicle UI.
- Booking and cell routes have safe, uncluttered navigation.
- Detection and interaction anchors survive swapping the visual model.
- Hero/mid/far budgets are met; tiny details do not cast shadows.
- Imported models contain no executable or interactive third-party instances.
- No manufacturer, police-force or council branding is used without permission.

## Provenance and licensing

- GOV.UK text and many diagrams are generally offered under the Open Government Licence v3.0, but check each document for third-party exceptions and record attribution.
- Government traffic-sign diagrams are the correct design reference; preserve source/revision metadata in the art repository.
- Manufacturer photos, CAD, logos, housing designs and datasheets remain manufacturer intellectual property. Use them as proportion and engineering references; do not redistribute their meshes, trace logos or market an exact branded replica without permission.
- Police-force photography and videos are reference material, not automatically reusable texture content.
- Creator Store/free-model status does not prove that a mesh, vehicle badge, logo or texture was uploaded by its rights holder. Sanitising scripts solves code risk, not copyright risk.
- Prefer original RoleplayOS meshes, genericised equipment housings and fictional agency branding. Keep a provenance record containing source URL, author, licence, download date, modifications and final asset owner.
