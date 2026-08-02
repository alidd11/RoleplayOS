# Roblox group integration

## Universal Projects production links

- Experience entry: Universal Projects (`33809042`). Rank 1 or above is required in production.
- Standard policing: UP Hampshire & Isle of Wight Constabulary (`34720334`). This includes Student Constable through Chief Constable.
- Armed Response: UP Armed Response Unit (`16985274`), combined with the main constabulary group.
- Roads Policing: UP Constabulary Divisional Hub (`33815770`), combined with the main constabulary group.
- Ambulance: UP East of England Ambulance (`33840360`).
- Fire: UP Norfolk Fire and Rescue Service (`14293067`).
- Transport: UK RP Linc Transit (`33360488`).
- Highway Patrol: MPS Training Grounds (`34022475`).
- Prison Service: Ministry of Justice HMCTS (`16361786`).

Whitelisted roles also retain the accepted RoleplayOS application requirement. Studio mock access bypasses external membership checks only for local testing. Until a dedicated Control group is supplied, Control temporarily uses Universal Projects as its group layer.

Whitelisted departments use server-side Roblox Group membership in addition to RoleplayOS application and suspension state. Each `GroupLinks` entry contains the real Roblox group ID, minimum accepted rank and display name.

RoleplayOS uses `GroupService:GetRolesInGroupAsync`, which supports Roblox's multi-role group memberships. It calculates the highest public rank returned for the configured group. Results are cached for the player session and discarded when the player leaves; menus and repeated role checks do not repeatedly call Roblox APIs.

Emergency role access is a combined `All` rule:

1. The RoleplayOS application or whitelist is active.
2. Roblox confirms group membership.
3. At least one returned group role meets the configured minimum rank.
4. Suspension and blacklist overrides remain clear.

API failures, missing configuration and stale or insufficient ranks deny access with distinct human-readable reason codes. Clients cannot submit group IDs, ranks or membership claims. Group membership is not used as a replacement for in-game qualifications or specialist training.

Before production, replace each `GroupId = 0` in `Config.GroupLinks` with the corresponding Roblox group ID and set the minimum rank deliberately. Test a non-member, ordinary member, qualifying rank and group owner in a private test server.

Private communities use a separate dynamic group link. The private-server owner enters a group ID during community creation; the server verifies ownership with `GetGroupInfoAsync`, persists the verified name and emblem, and maps live group ranks through `Communities.GroupRoleRanks`. This dynamic ID never grants access to Police, Ambulance, Fire or Control roles unless it is also explicitly configured under `GroupLinks`.
