# Levels and XP

Progression is civilian-character specific and server authoritative. `ProgressionService:Grant` accepts rewards only from server gameplay services; there is deliberately no client XP-grant endpoint. Each grant requires a unique reward ID, named track, positive integer amount below the configured cap and a server-defined reason code.

The default curve begins at 100 XP and grows by a factor of 1.18 per level, capped at level 100. `LevelProgression` calculates deterministic total thresholds, current-level progress and maximum-level state. Global XP and named tracks such as `Job:DeliveryDriver` progress independently using the same curve. Configuration owns the curve and caps.

Completed validated shift tasks award the configured job XP. The employment record mirrors that job track's XP and level as its experience and grade. Duplicate task reward IDs are rejected. Recent history is capped at 100 entries and replay IDs at 500 entries to bound profile size; sensitive grants are audited.

Physical job adapters must issue server-side task proofs through `ShiftService`. Clients must never provide XP amounts, levels, reward reasons or completion authority.
