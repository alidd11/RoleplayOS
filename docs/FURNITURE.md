# Furniture

Stores expose configured items and prices. Purchases debit through EconomyService and create owned inventory IDs. Placement requires owned character, item and property access; it validates finite serialised transforms, permitted yaw, room bounds and capacity. A server collision callback is mandatory before production release.

Move, remove and sell operations should reuse placement ownership checks and stable placement IDs. Never accept arbitrary assets, prices or unchecked world coordinates.
