# Access control

Access rules support public, gamepass, application, rank, qualification, department, whitelist, staff, temporary and combined access. Suspension and blacklist checks override all ordinary rules. Evaluations return `Allowed`, a stable reason code, human-readable message and non-sensitive metadata.

Whitelisted teams can require Roblox Group membership and minimum rank through a `Group` rule. Emergency roles combine this with the approved application state. See [Roblox group integration](ROBLOX_GROUPS.md).

Locked catalogue entries remain visible unless `DisplayWhenLocked` is false. Gamepass denials include prompt metadata; application and qualification denials explain the next action. The client may display or prompt, but every protected server action evaluates access again. Marketplace ownership is checked through Roblox and refreshed after the purchase-finished signal.
