# Server review — 19 August 2026

Findings from a review of `src/server/Services` and `src/shared`, at commit
`1df0f9f`. Emergency lighting was excluded because it was being worked on
concurrently.

**Verification status:** each item below was traced by the reviewer to the lines
cited and marked CONFIRMED or SUSPECTED there. They have *not* been independently
re-verified since. Re-check before acting on any of them — particularly the two
that involve taking money.

## 1. Two live game passes grant nothing

`Config.luau:528` `PremiumVehicles` (199 R$) and `:626` `GangSystemAccess`
(499 R$). Neither key nor id (`1936590544`, `1941013627`) is read anywhere
outside config. There is no gang system in the codebase at all, and no vehicle
`Access` rule references the premium pass. `GamepassService:RefreshAll` caches
ownership and nothing ever consults it.

This is the same shape as the `EquipmentPasses` fault the comment at
`LoadoutService.luau:304` records as already fixed once, and the same as the
`CivilianShotgun` / `CivilianRifle` blocker in `RELEASE_AUDIT.md`. **A player pays
499 Robux and receives nothing.** Delist or bind them.

## 2. Early-release credit clears the sentence even when release fails

`CustodyService.luau:196` and `:878`. `_completeSentence` zeroes
`RemainingSeconds` at the top, then can still return false for
`CIVILIAN_SPAWN_NOT_CONFIGURED`, a failed `RoleService:Assign`, or a failed
`SpawnService:Spawn`. The caller's rollback restores only the credit.

Serving player, one credit, no `Spawns` entry with `TeamName == "Civilian"`:
sentence cleared, credit refunded, free and still holding the credit. Repeatable
every sentence. `DeveloperProductService:_process:125` reaches the same path from
a receipt.

## 3. Vehicle purchase can take the money and not deliver

`VehicleOwnershipService.luau:220`. `Purchase` debits then calls `Create`, which
can fail at `_allocate` with `REGISTRATION_ALLOCATION_FAILED` or
`REGISTRATION_STORE_UNAVAILABLE`. Neither refunds. Buy a £45,000 car during a
DataStore outage and the money is gone with no vehicle.

`NetworkService.luau:814` also maps a message for `REGISTRATION_UNAVAILABLE`,
which this path never returns, so the player sees only the generic failure.

## 4. Duty start races a leaving player into a permanent phantom unit

`DutyService.luau:229`. `Begin` checks presence, then yields through
`UniformService:Apply`, `ApplyEpaulettes` and `ShoulderNumberService:Callsign`
(which can spend seconds in `_retry` backoff). If the player disconnects in that
window, `End` runs and clears `active`, then execution resumes:
`UnitService:Register` has no presence check and re-inserts the unit, and `:285`
indexes the nil `active` entry and raises. The unit stays on every dispatcher's
board for the life of the server.

## 5. Removing a vehicle skips its final telemetry write and leaks state

`VehicleSpawnerService.luau:556`. `Remove` clears `self.active[userId]` *before*
destroying, so the `Destroying` handler's `if self.active[...] == vehicle` guard
is already false — `_persistTelemetry(userId, true)` never runs and
`self.telemetry[userId]` is never cleared. Taken on death and on
`PlayerRemoving`, so a driver who disconnects loses up to 15 seconds of mileage
and fuel, and the entry retains a strong reference to the destroyed model for the
life of the server. The replacement path in `Spawn:1042` has the two lines the
right way round.

## 6. Pending transfer refunds are never reconciled

`EconomyService.luau:68`. `ReconcilePendingTransfers` is called once, from
`Start`. At that moment no player is present and no character is selected, so
every queued record fails both conditions and is written straight back. When a
transfer destroys money, the record queued for refund is never acted on and the
index grows monotonically. Run it from `PlayerAdded` after the profile settles,
or on a timer.

## 7. Per-player connections on the server-lifetime list

`MeleeWeaponService.luau:139` (one `CharacterAdded` per join **plus one
`Humanoid.Died` per respawn**, forever), `IdentificationService.luau:266` (two
per join, no `PlayerRemoving` at all), `CustodyService.luau:766` (one per join).
`DutyService.luau:21` documents this exact bug being fixed with a keyed
`playerConnections` map; these three were missed.

## 8. `SESSION_OWNERSHIP_LOST` retried as if transient

`DataService.luau:775`. Retried four times with 1+2+4s backoff plus budget waits,
though it is a settled outcome. `Load:617` already passes a `final` predicate for
the equivalent `PROFILE_SESSION_LOCKED`. With `ShutdownSaveSeconds = 16`, one
such profile can consume the whole shutdown window and abandon everyone else's
save.

## 9. Early-release products advertised but unbuyable

`Config.luau:829` — all three `PublicEarlyRelease.Products` have `ProductId = 0`,
so `DeveloperProductService` filters them out and the grant branch is dead code.
`CustodyService:GetPolicy:96` still returns them to clients, which will prompt a
purchase against product id 0.

## 10. Dead config keys

`Config.luau:284` `Groups.WarmSpacingSeconds` — no readers; the spacing is
actually done by `WebCallPacer`, so tuning this does nothing. `Config.luau:375`
`Characters.DeletionConfirmationSeconds` — no readers, and no character deletion
feature exists.

## 11. Attributes written and never read

`MoneyDropService.luau:134` `RoleplayOSCashDropId`; `LoadoutService.luau:47`
`RoleplayOSLoadoutId` (`ClearIssued` keys on `RoleplayOSDutyIssued` instead);
`LoadoutService.luau:362,372` `RoleplayOSEquipmentPassId`.

## 12. MoneyDropService destroys cash on shutdown — suspected

`MoneyDropService.luau:268`. `Destroy` removes every live drop with no reason, so
the part goes and `_remove:56` skips the audit entirely. The cash was debited at
`:208`, so it leaves the economy silently. May be an intended sink; the missing
audit line is not defensible either way.

## Checked and sound

Recorded so it is not re-covered: `NetworkServer`'s in-flight slot accounting and
handler deadline; all 72 endpoints having explicit rate-limit entries;
`AccessEvaluator`'s `Combined` empty-rules denial; `EconomyService:Transfer`'s
ascending-UserId lock ordering; `CustodyService`'s post-filter revalidation;
`GamepassService`'s purchase-signal grant; and `RegisterEvent` timing.
