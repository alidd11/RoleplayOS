# Speed cameras

Place a compatible camera model in the world. Fixed and average-speed detection
volumes using the existing RoleplayOS tags are also supported.

## How a camera is found

A model counts as a camera when it holds a part named `Sensor` and a
`Configuration` containing a `SpeedLimit`, which is what the camera kit builds.
They are found by that shape rather than by a tag, so a camera dropped into the
map works on the next server start and no list anywhere needs updating.

The kit's own script inside the model is **disabled automatically**. Leaving it
running would fine twice, and its own attempt fails regardless: it subtracts
from a `leaderstats` value this game does not have, so it raises rather than
charging anybody. It is disabled rather than destroyed, so the model is still
the kit's model and the change is undone by ticking one box.

Speed limits are still read from each model's `Configuration.SpeedLimit`, so
setting a limit works exactly as the kit intends.

Set optional `CameraId` and `Location` attributes on the camera model. The ID is
stored with every offence and must remain stable after the camera is moved or
renamed; Location is the player-facing road or area name shown in records.

The sensor may touch any part of a vehicle. RoleplayOS resolves the complete
assembly and its occupied `VehicleSeat`; the seat itself does not need to pass
through the sensor.

## Tagged and average-speed cameras

- Tag a fixed detection volume `RoleplayOSSpeedCamera` and set its optional
  `SpeedLimitMph`, `Location`, and `CameraId` attributes.
- Tag the first average-speed volume `RoleplayOSAverageSpeedEntry` and the last
  `RoleplayOSAverageSpeedExit`.
- Give both average-speed volumes the same `CorridorId` and `SpeedLimitMph`.

Average speed is calculated from the distance between the two volumes and the
server-measured journey time. Incomplete journeys expire automatically.

## The blue light exemption

An emergency driver on a response is not speeding, they are responding. The same
driver with the lights **off** is speeding in a marked car, and is fined like
anybody else.

The exemption therefore belongs to the response, not to the person or the
vehicle, and it is judged at the moment the camera reads — the only moment it is
true of. A team allowlist cannot express this: it is all or nothing per team, so
an emergency driver would be either never fined or always fined.

Both must hold:

1. **The blue lights are on**
2. **The driver is on duty with an emergency service** — without this, anybody
   who got hold of a marked car and found the light switch would be exempt

`Config.RoadSafety.ExemptRequiresDuty = false` drops the second.
`ExemptOnEmergencyLights = false` removes the exemption entirely.

The camera only flashes when somebody is actually fined. Flashing a responding
ambulance and then not fining it tells the driver they were caught when they
were not.

## Telling whether the lights are on

Lighting systems differ as much as chassis forks do, so nothing here assumes
one. `Config.EmergencyLights` is a list of places to look:

- every name in `AttributeNames`, as an attribute on the **vehicle model** and
  on its **driver seat**
- then as an attribute or a `ValueBase` inside each folder in `ValueFolderNames`

The first that reads as on wins. A boolean `true`, any number above zero, or any
non-empty string not listed in `OffValues` counts as on.

> **If the exemption is not firing**, turn the lights on in Studio and watch
> which attribute or value changes, then add that name to `AttributeNames`.

A vehicle whose lights cannot be read is simply never exempt, so a wrong guess
costs an emergency driver a fine rather than letting every civilian off.

## Who gets the fine

The registered keeper where the plate resolves to one, and the driver otherwise.
A camera can read a plate off a civilian's own car, but a service vehicle
belongs to nobody and somebody should still answer for driving it at seventy
through a thirty.

Fines and penalty points land on the character's driving record, so they appear
in the MDT and in the person record an officer searches.

With `Config.RoadSafety.AutomaticallyDebitFines` enabled, payment goes through
the server-authoritative `EconomyService`. Sufficient funds produce a matching
economy transaction and mark the fine paid. If the balance is too low, no money
is fabricated or taken below zero; the fine remains unpaid on the driving
record. The imported pack's leaderstats scripts are not required.

## For another camera system

`ServerStorage.RoleplayOSIssueFine` is a `BindableFunction` taking the same
request, for a camera that wants to do its own detecting:

```lua
local issued, reason = game:GetService("ServerStorage")
    :WaitForChild("RoleplayOSIssueFine")
    :Invoke({
        Registration = plate,
        Mph = measured,
        LimitMph = limit,
        Vehicle = vehicleModel,
        Driver = driverPlayer,
		-- Set only for a penalty deliberately issued by an officer. Automatic
		-- camera detections omit this field.
		IssuingOfficer = officerPlayer,
    })
```

## Whitelisted police Discord reports

Police-issued penalties can be posted to Discord guild `1532864611706077194`,
channel `1534723525275811891`. A channel link cannot receive messages, so create
an incoming webhook in that channel and save its complete URL as the Creator Hub
secret `RoleplayOSSpeedingFinesWebhook`. Enable HTTP requests for the experience,
then set `Integrations.Discord.SpeedingFines.Enabled` to `true` in
`EDIT_HERE/01_Deployment`.

Delivery requires all of the following and fails closed:

1. the current server kind is exactly `Whitelisted`;
2. `IssuingOfficer` is on active Police duty;
3. Roblox confirms that officer belongs to the configured Police group; and
4. the fine has already been persisted in RoleplayOS.

Public gamepass access, non-whitelisted servers and automatic cameras never
enter the Discord queue. A webhook failure is logged but
cannot delay, cancel or roll back the in-game penalty.

| Reason | Meaning |
| --- | --- |
| `EXEMPT_EMERGENCY_RESPONSE` | On a blue light run. Not an error. |
| `WITHIN_TOLERANCE` | Under the limit plus the tolerance. |
| `KEEPER_UNAVAILABLE` | Nobody in the server to fine. |
