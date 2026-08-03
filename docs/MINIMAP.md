# Vector minimap

RoleplayOS renders a minimap from tagged world geometry. It does not require an uploaded image, duplicate the map in a `ViewportFrame`, or send map geometry over remotes.

## Studio setup

Use Studio's Tag Editor to apply these tags:

- `RoleplayOSMinimapBounds` to one anchored, transparent part covering the playable map. Its rotation defines north.
- `RoleplayOSMinimapRoad` to simple anchored road parts. Their X/Z size and Y rotation are reproduced as vector rectangles.
- `RoleplayOSMinimapPOI` to a part or attachment marking a point of interest.

A major point of interest can have a `MinimapLabel` string attribute and a `MinimapColour` Color3 attribute. Keep labels opt-in and sparse so they remain legible. The minimap stays hidden until a bounds part exists, so an incomplete map never shows an empty player-facing panel.

## What the player sees

The minimap draws a window of fixed radius centred on the player rather than the whole mapped area. A region-sized world projected whole leaves every road a few thousandths of the surface wide, which reads as a smear rather than a road network, so the window keeps scale constant however large the world becomes. The player marker therefore stays at the centre and only its heading changes.

`Config.Minimap.WindowRadius` sets how much of the world is visible either side of the player, and `RedrawDistance` how far they travel before the picture is redrawn.

## Cost

Two passes are deliberately separated. Collecting tagged instances is the only work proportional to the size of the map, and it runs at most once per `RecollectSeconds` however many parts stream in or out between. Drawing considers only what falls inside the window, so frame cost is set by what is near the player rather than by how large the world is.

`MaximumRoads` and `MaximumPoints` bound what is drawn within that window. Roads should remain coarse map geometry rather than every decorative part: a smaller number of longer tagged parts costs less to collect and reads better than many short ones.

The terminal's tactical map shares this geometry but draws it at selectable zoom levels, since control needs the whole picture as well as a close view. See [MDT and dispatch](MDT_DISPATCH.md).

Street and district names come from a separate set of tagged zones. See [Street and district names](LOCATIONS.md).
