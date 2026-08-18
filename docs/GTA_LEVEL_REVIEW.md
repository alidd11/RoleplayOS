# What it would take to be GTA-level

A review of RoleplayOS at `c01fc7e`, against the question "how do we get this to
the standard of GTA". Every number below was measured against the tree or a
running server rather than estimated.

## Where you actually are

48,776 lines across 165 files. 77 services. That is not a small project, and the
parts that exist are built to a genuinely high standard.

| Area | Evidence |
| --- | --- |
| Police procedural | Custody 1082 lines, MDT 1264, plus Warrant, ANPR, Dispatch, Incident, PersonRecord, VehicleRecord, RecordIndex, Identification, ShoulderNumber |
| Employment | Duty, Shift, Qualification, Application, Department, Station, Payroll, Role |
| Property | Property, PropertyInstance, EstateAgent, Furniture, FurniturePlacement, FurnitureStore |
| Persistence | DataService 1001 lines, `UpdateAsync` on shared keys, profiles, characters, owned vehicles |
| Comms | Phone 1182, Radio, PhoneVoice |
| Identity | Avatar creator with catalog proxy and appearance validation |

If the question were "is this a serious framework", the answer is yes. The
custody and records systems are more detailed than most published RP games have.

## The actual problem, and it is one problem

**You have built the response side of a world to an extraordinary standard, and
the thing being responded to does not exist.**

Measured:

- **Zero traffic. Zero pedestrians. Zero NPCs.** No service in `src/server/Services`
  mentions any of them. Only two services use randomness at all: `BankRobbery`
  and `DataService`.
- **Dispatch calls are player-created only.** `CallService:Create` is invoked by
  players; nothing generates an incident. Police have nothing to respond to
  unless another player commits a crime.
- **There are almost no crimes to commit.** "Wanted" appears once in the entire
  server tree, as a vehicle flag inside `ANPRService`. No pursuit system, no
  heat, no escalation.
- **One criminal activity exists**: the bank. 200 seconds, 400 second cooldown,
  £1800–4500.
- **One civilian job exists**: `TaxiDriver`. **One business**: `Workshop`.
- **Payroll pays police £2600/hour.** Emergency services are the only reliable
  income, so the economy pushes every player into a uniform.

That last point is the crux. GTA's loop is *the world generates activity → the
player engages → there are consequences*. Here the first step is missing
entirely, which means the second is missing for everyone not in a uniform, and
the third — the part you have actually built, and built well — almost never
fires.

A new player who is not on an emergency team currently has: drive a car, buy
furniture, rob one bank on a cooldown, drive a taxi. That is the whole game for
them.

## What "GTA-level" decomposes into

Ranked by leverage on that problem, not by difficulty.

### 1. A world that is alive without players — the single highest-value item

Traffic and pedestrians are the difference between a map and a city. They also
solve the dispatch problem for free: an NPC-populated world can generate RTCs,
shoplifting, disturbances, abandoned vehicles, and suddenly your dispatch,
incident, custody and records systems have a reason to run.

This is genuinely hard on Roblox and is where most of the engineering budget
should go. The cheap version — a pooled set of NPC vehicles on spline paths with
aggressive distance culling, plus streamed pedestrian crowds — is achievable and
would transform how the place feels. Do not simulate what nobody can see; a few
dozen agents near the player, recycled, reads as a city.

### 2. A crime and consequence loop

Concretely, in order:

- **A wanted/heat system.** A persistent per-character level with decay, driven
  by observed offences. You already have `OffenceTariffs` with 19 statutes and
  a custody system that consumes them — heat is the missing middle.
- **Pursuit mechanics.** Line of sight, evasion, radio callouts. Your `Radio`
  and `Dispatch` services already carry this; nothing feeds them.
- **More criminal activity than one bank.** Shops, ATMs, vehicle theft with a
  chop shop, drug-free contraband (given the ToS constraint you already work
  under — smuggling untaxed goods, stolen electronics, counterfeit currency all
  work and are ToS-safe).

### 3. The driving has to carry the game

In GTA people spend most of their time driving. Yours is A-Chassis with no
damage model, no repair, no insurance, no tuning, no customisation — grep finds
none of them. Three things, in order of felt impact:

- **Damage and deformation.** Even simple part-level damage with degraded
  handling changes every chase and every RTC.
- **Customisation.** Colour, wheels, plates, livery. This is also your strongest
  monetisation surface and it is entirely absent.
- **A garage/insurance loop.** You have `GarageService`; it does not close the
  loop of crash → recover → pay → repair.

### 4. Content volume

15 vehicle `.rbxm` files. GTA-level is not reachable at that number for a game
where driving is the core verb. This is asset acquisition, not engineering, and
it is the one item on this list you can buy your way through.

### 5. The things that make it feel expensive

Weather, interiors, time-of-day tied to `UKTimeService`, ambient audio zones,
radio stations. None exist. Individually small, collectively the difference
between "a Roblox game" and "a world".

## What I would not do

- **Do not add more police features.** That side is already past the point of
  diminishing returns relative to everything around it. Another MDT tab does not
  help a game where nothing generates incidents.
- **Do not chase graphical fidelity.** Roblox will not win that comparison and it
  is not why GTA feels the way it does.
- **Do not build fuel, hunger, or other attrition systems** until there is
  something to interrupt. They add friction to a loop that does not exist yet.
  (Fuel is correctly switched off at `Config.VehicleData.FuelEnabled`.)

## A sequence I would actually follow

**Phase 1 — give the world a pulse.** Ambient traffic and pedestrians with hard
culling. Nothing else. This is the foundation everything else stands on, and it
is the change a returning player would notice within five seconds.

**Phase 2 — close the crime loop.** Wanted level with decay, pursuit state,
three or four repeatable crimes beyond the bank. Now dispatch has input, police
have work, and custody has throughput. The systems you already own start
carrying the game.

**Phase 3 — make driving matter.** Damage, repair, insurance, customisation.

**Phase 4 — volume and texture.** Vehicles, jobs, businesses, weather, interiors.

Phases 1 and 2 are where essentially all of the perceived gap lives. Phase 1
alone would change the answer to "what is there to do here" more than the last
several thousand lines of work has.

## The honest framing

GTA is a decade of work by a studio of thousands, and matching it is not the
useful target. What is achievable, and what actually produces the same feeling,
is narrower: **a world that is doing something when you arrive, and a reason to
be in it that is not a uniform.**

You are much closer to that than the list above suggests, because the expensive,
unglamorous half — persistence, records, identity, employment, custody, property
— is already built and working. What is missing is the half that generates
events. That is a smaller body of work than what has already been done, and it
is worth more than anything else currently on the roadmap.
