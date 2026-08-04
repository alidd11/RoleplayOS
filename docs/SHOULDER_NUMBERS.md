# Shoulder numbers

Every member of an emergency service carries a shoulder number, issued once and
never reissued. Members put these numbers in their Discord display names, so a
number that moved between people would make every one of those names wrong. The
design exists to make that impossible.

## How a number is issued

A number is claimed the first time a player goes on duty in a service, not when
they join the group and not when the duty profile is created. Nobody holds a
number for a service they have never worked.

Allocation is a counter held per department in the `RoleplayOS_ShoulderNumbers_v1`
store, incremented under `UpdateAsync`. Two servers claiming at the same moment
cannot land on the same number, and finding the next free one costs one write
rather than a scan of every existing holder.

Each service starts its own block, so the number alone identifies the service:

| Service | First number |
| --- | --- |
| Police | 1000 |
| Ambulance | 3000 |
| Fire | 5000 |
| Control | 7000 |
| Transport | 7500 |
| Highways | 8000 |
| Prison | 9000 |

Numbers only ever move forward. A server that dies between claiming the counter
and writing the holder record burns a number without assigning it; that is the
safe direction to fail, because a gap in the sequence is invisible whereas a
number issued twice would put two officers on air as the same unit.

Numbers are held **per department**. Somebody serving in both Police and Fire
holds one in each, which is how the real services work and costs nothing extra:
allocation happens once per person per service, ever.

## Ranks

`Config.Departments[id].Ranks` is the ladder, and a profile stores its rank as an
index into it. Each entry declares a name, an abbreviation and whether the rank
wears a number:

```lua
{ Name = "Constable", Abbreviation = "PC", Numbered = true },
{ Name = "Inspector", Abbreviation = "Insp", Numbered = false },
```

In the British services shoulder numbers are worn by the junior ranks and
dropped at the point rank insignia takes over, which is why an inspector has no
collar number. `Numbered` encodes exactly that boundary.

A promoted officer **keeps** their number even past the ranks that display it, so
a demotion restores the number they always had rather than issuing a new one.

> **Ranks may be appended, never reordered or removed from the middle.** A
> profile stores an index, so changing the order silently repromotes or demotes
> everyone above the change.

## Callsigns

`ShoulderNumberService:Callsign(player, profile)` returns what the unit is
called on air and on the unit list:

- A numbered rank gives `PC 1042`, `FF 5017`, `Para 3006`.
- A rank above the numbered ranks gives the abbreviation alone: `Insp`, `Ch Supt`.

An explicit `Callsign` already set on the duty profile still wins, so a unit
given a bespoke one by staff keeps it.

## Staff roster

`GetShoulderNumberRoster` returns the numbers held by players **currently in this
server**, for reconciling Discord display names against the game. There is no
index of every profile that has ever existed, so this is a live view rather than
a full roster.

It is read-only. Nothing in the framework assigns, reassigns or frees a number.

Access is not a separate permission. The management line is the rank at which a
service stops wearing numbers, which is already declared on the ladder: anyone at
or above it sees their own service's roster, and nobody sees another service's.

## Changing the settings

`Config.ShoulderNumbers`:

| Key | Meaning |
| --- | --- |
| `Enabled` | Turns issuing off entirely. Existing numbers stay on profiles. |
| `Format` | How the number is rendered, `%04d` by default. |
| `Start` | First number per department. |
| `DefaultStart` | Used by a department with no entry in `Start`. |

Raising a `Start` value after numbers have been issued is safe — the counter is
already past it and only moves forward. Lowering one is not: it has no effect,
because the counter is the authority, not the configuration.
