# PAVA implementation

The supplied PAVA package is retained in Studio quarantine as
`ServerStorage.RoleplayOSAssetQuarantine.PAVA_System_Source` for reference.
Its original scripts are not used: they accepted client-authoritative hits,
moved arbitrary tools into `Lighting`, disabled an arbitrary `SprintScript`,
and created accumulating input connections.

The live template is the sanitised tool at
`ServerStorage.RoleplayOSAssets.Tools.Services.Police.Shared.PAVA`. It has no
scripts, remotes, or screen GUI. RoleplayOS issues it to authorised police
roles only (`PoliceResponse`, `PoliceFrontline`, `ArmedResponse`, and
`RoadsPolicing`). Ambulance and fire loadouts do not receive PAVA because it is
police equipment.

Use is server-authoritative: the server checks police duty, possession of the
issued tool, target validity, distance, health, and a cooldown before applying
a temporary movement effect. It never removes tools or disables unrelated
scripts. The original 30-second duration is retained, with safe restoration.

## Animation publishing

The supplied `KeyframeSequence` objects remain in the quarantined source and
the template's animation IDs are intentionally blank until they are published
under the Universal Projects creator. The current Studio connector can inspect
and insert assets but cannot publish `KeyframeSequence` animations or select a
group creator, so no false or personal-owner IDs were inserted.

In Studio, for each sequence (`PAVA Equip`, `PAVA Equipping`, and optionally
`Itchy Eyes`): open it in Animation Editor, choose `… > Publish to Roblox`, set
Creator to `Universal Projects` (group `33809042`), submit, then copy the IDs
into the matching `Animation.AnimationId` properties on the sanitised template.
The client controller safely skips blank IDs, so PAVA remains functional while
the group-owned animations are being published.
