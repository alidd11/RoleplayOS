# Mobile phone

RoleplayOS Mobile is an original modern smartphone interface rather than a copy of a branded handset. It opens with the on-screen launcher or the `P` key and uses the selected civilian character's persistent phone identity.

Each character receives a stable UK-format mobile number. Players in the same live server can call by number, answer, connect and end a call. The call service is server-authoritative and prevents self-calls, double calls and answering another player's call. It models call signalling and roleplay state; Roblox does not expose a supported API for routing a private custom voice channel between two arbitrary players.

Texts are length-limited, rate-limited and filtered through Roblox `TextService` before either participant sees or stores them. Messages are capped per character to bound profile size. The current implementation intentionally supports online recipients in the same server; reliable offline or cross-server delivery needs a dedicated indexed message store rather than writing into another server's session-locked profile.

The 999 page asks for an incident and exact location. Both fields are filtered for broadcast, and a successful request creates an `Immediate` dispatch call. It never grants the caller MDT access and does not trust the client to set arbitrary dispatch fields.
