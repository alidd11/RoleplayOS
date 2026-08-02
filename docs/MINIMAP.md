# Vector minimap

RoleplayOS renders a minimap from tagged world geometry. It does not require an uploaded image, duplicate the map in a `ViewportFrame`, or send map geometry over remotes.

## Studio setup

Use Studio's Tag Editor to apply these tags:

- `RoleplayOSMinimapBounds` to one anchored, transparent part covering the playable map. Its X and Z dimensions define the minimap bounds, and its rotation defines north.
- `RoleplayOSMinimapRoad` to simple anchored road parts. Their X/Z size and Y rotation are reproduced as vector rectangles.
- `RoleplayOSMinimapPOI` to a part or attachment marking a point of interest.

A major point of interest can have a `MinimapLabel` string attribute and a `MinimapColour` Color3 attribute. Keep labels opt-in and sparse so they remain legible on the compact map. The minimap stays hidden until a bounds part exists, so an incomplete map never shows an empty player-facing panel.

Geometry is drawn only when tagged instances are added or removed. The player marker updates at the configured eight times per second. Limits in `Config.Minimap` protect the client from accidentally rendering excessive tagged detail; roads should remain coarse map geometry rather than every decorative part.
