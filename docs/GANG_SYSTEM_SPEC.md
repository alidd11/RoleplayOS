# Gang system — agreed design

Decisions taken 19 August 2026. This exists to make `GangSystemAccess`
(499 R$, `1941013627`) grant something: it is currently on sale and wired to
nothing, which `docs/SERVER_REVIEW_2026_08_19.md` lists as the most urgent item
in the repo.

## The four decisions

**Territory gives passive income and a spawn point.** A held territory pays the
gang a trickle while they hold it and members spawn there rather than at the
civilian spawn. Both sides reuse services that already exist — `EconomyService`
for the payout and `SpawnService` for the spawn.

**Only the leader needs the pass.** One purchase, and the holder can add anyone
free. This sells the pass on running a gang rather than on joining one, and it
means a gang can actually fill up.

**Vehicles come from a spawner at the territory, shared by the gang.** Pedal
bikes and a couple of Surrons. `VehicleSpawnerService` already authorises by
department and division against a tagged spawner, so a gang spawner is the same
shape with a different authority check.

**Territories are contested, and police can clear a claim.** Chosen over the
simpler uncontested version deliberately. It is the most work, and it is also the
only option that produces the thing `docs/GTA_LEVEL_REVIEW.md` identifies as
missing: something that generates activity for the police systems to respond to.
Dispatch, custody, MDT and records are all built and largely idle because nothing
creates incidents.

## What this needs building

Roughly in dependency order.

1. **Gang membership and persistence.** A gang record on the leader's profile —
   name, members, territory — and a membership pointer on each member's. Invite
   and accept through the network layer, with the leader's pass checked
   server-side on invite rather than trusted from the client.
2. **Territory zones.** Tagged parts in the map the way `RoleplayOSZone` already
   works for `LocationController`, each with an id and a name. Claim state lives
   on the server and replicates as attributes.
3. **Claiming and contesting.** Presence-based: a gang with more members standing
   in a zone than the holder slowly flips it. Needs a rate, a threshold and a
   grace period, all in config so they can be tuned without a code change.
4. **Police clearing.** An on-duty officer in the zone halts a contest and, held
   long enough, resets the claim to unowned. This is the hook into the existing
   police loop and should raise a dispatch call when a contest starts.
5. **Income.** Paid on the same interval `PayrollService` uses, from the same
   economy paths, so it cannot double-credit and shows in the audit log.
6. **The territory spawner.** A tagged spawner authorised by gang membership
   rather than duty department, offering the bikes and Surrons.

## Constraints to hold to

**ToS.** Nothing here touches controlled substances or alcohol — the same line
already enforced across offences and search powers, where the checks grep for
both by name so neither can creep back. A gang here is a territorial group with
vehicles and a base, not a drug operation.

**Griefing.** Contested territory is the one part of this that invites abuse.
Whatever the contest rules end up being, they need a floor on how often a zone
can change hands and a way for the police clear to actually settle it, or a
larger gang will simply hold everything.

**Money.** Income enters the economy and needs the same care as the other paths
the server review flagged — credited through `EconomyService`, audited, and not
repeatable by rejoining. Get this wrong and it inflates faster than payroll.

## Where it starts

`GamepassService:RefreshAll` already checks and caches ownership of this pass and
nothing consults the result. That cache is the entitlement check the invite flow
needs, so the first piece of work has a foundation waiting for it.
