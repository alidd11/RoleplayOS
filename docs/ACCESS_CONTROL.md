# Access control

Access rules support public, gamepass, application, rank, qualification, department, whitelist, staff, temporary and combined access. Suspension and blacklist checks override all ordinary rules. Evaluations return `Allowed`, a stable reason code, human-readable message and non-sensitive metadata.

Locked catalogue entries remain visible unless `DisplayWhenLocked` is false. Gamepass denials include prompt metadata; application and qualification denials explain the next action. The client may display or prompt, but every protected server action evaluates access again. Marketplace ownership is checked through Roblox and refreshed after the purchase-finished signal.
