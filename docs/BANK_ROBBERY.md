# Bank robbery

Bank robbery gameplay is server-authoritative and available in both public and
whitelisted servers. Tag the bank's interaction model or part with
`RoleplayOSBankRobberyTarget` and place a `ProximityPrompt` beneath it. Set the
optional `Location` attribute to the wording dispatch should see.

The prompt starts a timed robbery. The initiating civilian must keep an active
character, remain alive and stay within the configured completion radius. A
successful robbery credits carried cash through `EconomyService`; clients never
choose the reward. Starting a robbery creates the existing `BankRobbery`
emergency trigger, which raises a dispatch/MDT call and alerts on-duty Police and
Control users.

## Supplied visual asset

The supplied source model is:

`/Users/macbook/Desktop/UKRP Portsmouth/Bank Robbery/Bank_robbery_System_V2_Beta_wl_obs 2.rbxm`

Its `MainHandler` is deliberately not imported: it is heavily obfuscated and
cannot be reviewed safely. To use its scenery, make a separate copy in Studio,
delete every `Script`, `LocalScript`, `ModuleScript`, `RemoteEvent`,
`RemoteFunction`, `BindableEvent`, `BindableFunction`, `ObjectValue`, tool and
GUI, then retain only the required static parts, meshes, constraints, sounds and
effects. Run content validation on the cleaned copy before placing it in the
map. Never copy the `Sentinels City` folders or the supplied handler into the
live DataModel.
