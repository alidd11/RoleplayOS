# Street and district names

The name of the place a player is standing in is shown along the top of the screen. Place names live in the map, not in configuration: the framework has no list of streets compiled into it, so naming a world is a mapping job and needs no code change.

## Studio setup

A zone is an ordinary anchored part covering the ground a name applies to. Make it `Transparency = 1` and `CanCollide = false`; it only needs to cover the height a player walks at. Apply the `RoleplayOSZone` tag with Studio's Tag Editor, then set its attributes:

| Attribute | Type | Required | Purpose |
| --- | --- | --- | --- |
| `StreetName` | string | Yes | Shown in large text, for example `Commercial Road`. A zone without one is ignored. |
| `DistrictName` | string | No | Shown smaller beneath, for example `Southsea`. |
| `Priority` | number | No | Decides which zone wins where zones overlap. Defaults to zero. |

Build one zone, then duplicate and resize it for each street. Duplicating carries the tag and every attribute, so only `StreetName` normally needs editing.

## Layering districts under streets

`Priority` exists so a large area can enclose smaller ones without hiding them. Cover a whole district with a single zone at the default priority carrying only a `DistrictName`, then lay individual street zones over it at a higher priority. The street wins wherever one exists, and the district shows through everywhere else, so no part of the map has to be tiled exhaustively to be named.

Where two zones share the highest priority the result is not defined, so give overlapping streets distinct priorities rather than relying on which was tagged first.

## Cost

The zone containing the player is resolved through the engine's spatial index, so the check costs the same whether the map has ten streets or ten thousand. Only rebuilding the query filter is proportional to the number of zones, and that runs at most once per `Config.Locations.RecollectSeconds` however many zones are tagged or untagged in between.

Zones are read on the client. They carry names only, never gameplay state, so nothing is trusted from them.

## Behaviour

The name sits below Roblox's own top bar, measured rather than assumed, and steps down while the player is driving so it does not cover the vehicle readouts. A change fades in, unless the player has turned interface motion off in Advanced settings, in which case it appears without movement.

With no zones tagged the display stays hidden rather than showing an empty panel, so an unnamed map is simply silent. Tag one part first and confirm the name appears before naming a whole map.
