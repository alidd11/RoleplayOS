# Release audit — 7 August 2026

## Verdict

**Do not publish RoleplayOS to the live Portsmouth start place yet.** The source and deployment boundaries are healthy, but required content and owner-controlled production configuration are incomplete. Publish only to a private staging place after the blockers below are cleared.

## Automated evidence passed

- StyLua check over `src` and `tests`;
- Selene over `src` and `tests`: zero errors, warnings or parse failures;
- Rojo production-preserving project build;
- Rojo acceptance-place build;
- deployment project preserves unknown instances and does not own Workspace or Teams;
- all 48 currently registered client-callable endpoints have explicit rate limits;
- Python release scripts compile;
- Git whitespace/error check passes.

## Code and architecture fixes completed

- Public and official-whitelisted player progression now use separate persistence namespaces, including profiles, money, vehicles, MDT projections, registrations and shoulder numbers.
- Police warrant cards use the canonical server asset, survive respawn/duty refresh and present only to the targeted nearby player.
- Dispatch and MDT share one operational-terminal visual language while retaining separate control-room functions.
- Vehicle spawning is protected from optional imported-model render/streaming property failures.
- Every configured service has a unique dealer terminal and vehicle bay fallback, associated by stable terminal ID rather than location.
- Team objects are generated from configuration without Rojo replacing the production Teams service.
- Uniforms are selected through server-authorised changing-room prompts instead of being forced on team selection; original clothing is restored when duty ends.
- Production content validation now refuses to start when a required vehicle/tool template or content root is missing. Development continues with explicit warnings.
- The release gate now verifies configured filesystem assets, and a separate read-only script verifies the live sale state and creator of every configured game pass.

## Blocking findings

1. Twenty configured vehicle/tool templates are missing from `server-assets`. The reviewed Warrant Card, Taser and Handcuffs templates are present; shared Radio/MDT, the ambulance MedicalBag and configured vehicles remain absent. Loose Workspace cars are not a production source and will not transfer to another place through the safe Rojo project.
2. All sixteen configured game passes currently report `IsForSale = false` and no positive Robux price. Creator ownership is correctly reported as Universal Projects, but universe association still needs checking in Creator Hub.
3. Shirt and trouser template IDs are empty for Police, Ambulance, Fire, Transport, Highways and Prison.
4. Control intentionally uses the main Universal Projects group mapping; this mapping has been reviewed and retained.
5. The framework is still in Development mode with Studio mock persistence and mock emergency access enabled.
6. Required world-model certification remains pending for CCTV, ANPR, speed cameras, custody furniture, dealership NPCs and dispatch furniture.
7. No source-only test can prove live DataStore failure behaviour, cross-JobId isolation, group membership, Marketplace ownership, voice eligibility or two-player presentation. The published staging acceptance matrix remains mandatory.

## Safe transfer outcome

When `real-baseplate.project.json` is connected to the actual Portsmouth place, Rojo will update only:

- `ReplicatedStorage/RoleplayOS`;
- `ServerScriptService/RoleplayOS`;
- `ServerStorage/RoleplayOSAssets`;
- `StarterPlayer/StarterPlayerScripts/RoleplayOSClient`.

It will preserve the map, Terrain, Lighting, Teams and unrelated systems. This transfer becomes complete only after approved vehicles, tools and interiors have been exported into the canonical `server-assets` paths. Location-bound objects remain in Workspace and are matched through tags/attributes; generated development fallbacks are not a substitute for reviewed production placement.
