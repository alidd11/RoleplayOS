# Speed cameras

Detection belongs to the camera system placed in the world. RoleplayOS decides
whether the driver should have been fined at all, what it costs, and records it
where the MDT can see it.

## Hooking a camera up

RoleplayOS puts a `BindableFunction` called **`RoleplayOSIssueFine`** in
`ServerStorage`. A camera script parented anywhere on the server can find it
without requiring anything:

```lua
local bridge = game:GetService("ServerStorage"):WaitForChild("RoleplayOSIssueFine")

local issued, reason = bridge:Invoke({
    Registration = plate,        -- required
    Mph          = measuredMph,  -- required
    LimitMph     = limit,        -- required
    Vehicle      = vehicleModel, -- optional, needed for the blue light exemption
    Driver       = driverPlayer, -- optional, defaults to the registered keeper
    Location     = "London Road",
})

if not issued and reason == "EXEMPT_EMERGENCY_RESPONSE" then
    -- On a blue light run. Do not flash, do not fine.
end
```

### If your camera exempts by team

A team allowlist cannot express this rule. It is all or nothing per team, so an
emergency driver is either never fined or always fined, and what you want is
"exempt only while responding".

**Empty that list** and let this decide instead. It knows whether the lights are
on and whether the driver is actually on duty, neither of which a team name can
tell you.

## The direct call

From inside RoleplayOS, the same thing without the bridge:

```lua
RoadSafetyService:IssueFine({
    Registration = "AB12 CDE",   -- required
    Mph          = 47,           -- required, what the camera measured
    LimitMph     = 30,           -- required
    Vehicle      = vehicleModel, -- optional, needed for the blue light exemption
    Driver       = player,       -- optional, defaults to the registered keeper
    Location     = "London Road",
    Kind         = "SpeedCamera",
})
```

It returns `true` when a fine was written, or `false` and a reason:

| Reason | Meaning |
| --- | --- |
| `EXEMPT_EMERGENCY_RESPONSE` | On a blue light run. Not an error. |
| `WITHIN_TOLERANCE` | Under the limit plus the tolerance. |
| `KEEPER_UNAVAILABLE` | Unregistered, or the keeper is not in the server. |
| `INVALID_REGISTRATION` / `INVALID_SPEED` | The call was malformed. |

A fine lands on the character's driving record, so it appears in the MDT and in
the person record an officer searches. Penalty points accumulate on the same
record.

## The blue light exemption

An emergency driver on a response is not speeding, they are responding. The same
driver with the lights **off** is just speeding in a marked car, and is fined
like anybody else.

The exemption therefore belongs to the response, not to the person or the
vehicle, and it is judged at the moment the camera reports — the only moment it
is true of.

Both of these must hold:

1. **The blue lights are on** (see below)
2. **The driver is on duty with an emergency service** — without this, anybody
   who got hold of a marked car and found the light switch would be exempt

`Config.RoadSafety.ExemptRequiresDuty = false` drops the second condition.
`ExemptOnEmergencyLights = false` removes the exemption entirely.

## Telling whether the lights are on

Lighting systems differ as much as chassis forks do, so nothing here assumes
one. `Config.EmergencyLights` is a list of places to look:

- Every name in `AttributeNames` is tried as an attribute on the **vehicle
  model** and on its **driver seat**
- Then as an attribute or a `ValueBase` inside each folder in
  `ValueFolderNames`

The first that reads as on wins. A boolean `true`, any number above zero, or any
non-empty string that is not in `OffValues` counts as on.

> **If the exemption is not working**, the surest way to find the right name is
> to turn the lights on in Studio and watch which attribute or value changes.
> Add that name to `AttributeNames`, or its folder to `ValueFolderNames`.

A vehicle whose lights cannot be detected is simply never exempt, so a wrong
guess costs an emergency driver a fine rather than letting civilians off.

## What was removed

The previous system did its own detection from three tags —
`RoleplayOSSpeedCamera`, `RoleplayOSAverageSpeedEntry` and
`RoleplayOSAverageSpeedExit` — including average speed traps. All three are
gone and nothing reads them, so those parts can be deleted from the map.
