# World asset certification ledger

This ledger is the release evidence for visible models that RoleplayOS describes as
realistic. An empty or `Pending` row means the corresponding model is not production-ready.
Runtime attributes alone are not sufficient proof.

| Kind | Intended UK reference | Source/licence | Studio model path | Reviewer | Status |
|---|---|---|---|---|---|
| `ANPRCamera` | [AXIS Q1700-LE official product manual](https://help.axis.com/en-US/axis-q1700-le), adapted to the chosen UK mounting installation | Pending | Pending | Pending | Pending |
| `CCTVCamera` | UK public-space PTZ or fixed camera plus [UK police CCTV requirements](https://www.gov.uk/government/publications/uk-police-requirements-for-cctv-systems/police-requirements-for-cctv-systems) | Pending | Pending | Pending | Pending |
| `CustodyFurniture` | [ACPO safer detention guidance](https://assets.publishing.service.gov.uk/government/uploads/system/uploads/attachment_data/file/117555/safer-detention-guidance-2012.pdf) and a selected UK custody-suite reference set | Universal Projects original / pending review | Pending | Pending | Pending |
| `DealershipNPC` | Contemporary UK dealership staff presentation | Universal Projects original / pending review | Pending | Pending | Pending |
| `DispatchFurniture` | [NPSA control-room guidance](https://www.npsa.gov.uk/building-protection/video-surveillance-access-control-detection-control-rooms/control-rooms) and selected UK emergency control-room references | Universal Projects original / pending review | Pending | Pending | Pending |
| `SpeedCamera` | Correct UK camera family plus the [Home Office speedmeter handbook](https://www.gov.uk/government/publications/home-office-speedmeters-handbook-fourth-edition-publication-no1505) | Pending | Pending | Pending | Pending |

## Replacement procedure

1. Place candidate artwork in a temporary quarantine folder and remove every script,
   remote, bindable, prompt and click detector.
2. Record the creator, asset identifier, licence and reference photographs or manufacturer
   literature. Do not use an asset whose redistribution rights are unclear.
3. Compare silhouette, proportions, installation height, mounting, materials and markings
   from all principal views. Use original or licensed markings only.
4. Verify pivot, scale, collisions, query/touch settings, mesh and texture budgets, then test
   desktop, mobile, gamepad and relevant VR/vehicle views.
5. Replace the previous visible shell in its department/world folder. Preserve RoleplayOS
   sensor tags only on the intended invisible functional volumes.
6. Give the replacement a new stable `RoleplayOSAssetId` and set
   `RoleplayOSReplacesAssetId` to the old ID. Delete the obsolete shell after confirming no
   references depend on it; the runtime audit rejects both IDs being present together. Record the new
   Studio path and reviewer here, then add `RoleplayOSWorldAsset` and the required
   certification attributes to the new top-level model.

No row may be changed to `Certified` from screenshots or metadata alone: the actual model
in the authorised development baseplate must be inspected and play-tested.
