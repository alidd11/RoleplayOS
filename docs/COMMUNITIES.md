# Private communities

RoleplayOS supports a public game alongside independently managed private roleplay communities. A community is a persistent record with a stable ID, owner, template, policy set, branding, version and membership map. It is not a separate trust boundary: all community administration is still validated by the game server.

Private Roblox servers derive a stable community ID from `game.PrivateServerId`. The private-server owner can initialise that community through the `CreatePrivateCommunity` endpoint. Reserved servers may later be routed to an existing community session using signed TeleportData; public servers remain community-neutral.

The default hierarchy is Owner, Administrator, Moderator and Member. Permissions are explicit strings with a wildcard reserved for owners. An actor may manage only lower-priority roles. Invitations are written atomically, accepted membership is recorded in both the community record and player profile, and decisions are audited. Suspended and banned members cannot pass community join policy.

Community policy controls open, approval or invite-only joining; whether civilian play remains public; whether membership is required; and named economy/rule presets. Community configuration selects presets rather than supplying arbitrary prices, rewards, tools or server code. Production additions should include session schedules, invite codes stored as hashes, moderation appeal records, owned-server discovery, branding moderation and MemoryStore presence.
