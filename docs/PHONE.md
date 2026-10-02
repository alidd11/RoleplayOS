# Mobile phone

RoleplayOS Mobile is an original modern smartphone interface rather than a copy of a branded handset. It is taken out by selecting the Phone tool in the toolbar, the way a handset is taken from a pocket, or with the `P` key; putting the tool away closes it. There is no on-screen launcher, so nothing competes with the rest of the interface for a corner of the screen. The handset uses the selected civilian character's persistent phone identity.

Its home screen is a grid of apps with a dock of pinned ones, and the heading and dock give way to whichever app is open. A wallet app shows the holder's own identity card. Reading your own card is not the same as presenting it: showing identification to another player still goes through the identification service, which requires the physical card in hand and the other player within range.

It also exists as a held toolbar `Tool` with a welded screen and a server-controlled flashlight. The home screen uses an icon dock and includes a Contacts app showing active characters in this server.

Each character receives a stable UK-format mobile number. Players in the same live server can call by number, answer, connect and end a call. The call service is server-authoritative and prevents self-calls, double calls and answering another player's call. Call signalling works for every player. Private audio routing must only be enabled after the experience accepts Roblox's Chat & Voice Groups API terms and enables `VoiceChatService.UseAudioApi`; ordinary proximity voice is not presented as a private phone channel.

Ended calls are retained for five seconds before cleanup. During that window,
another hang-up from either participant succeeds without repeating notifications,
voice teardown or resetting retention. It cannot release a newer call's busy
state. Other players still cannot end the retained call.

Texts are length-limited, rate-limited and filtered through Roblox `TextService` before either participant sees or stores them. The sender and recipient views are filtered concurrently, then the exact Player instances, profile sessions and active characters are revalidated before either inbox is mutated. A disconnect, rejoin or character switch while filtering therefore cancels the stale send instead of writing through a reused UserId. Messages are capped per character to bound profile size. The current implementation intentionally supports online recipients in the same server; reliable offline or cross-server delivery needs a dedicated indexed message store rather than writing into another server's session-locked profile.

Startup requires a Phone configuration table with finite whole-number limits:
`MaximumMessageLength` must be at least one and `MaximumMessages` at least zero.
Zero retention removes each message after appending; normal delivery still works.
Invalid or missing limits are refused before services start. Defaults remain
240 characters and 200 retained messages.

The 999 page asks for an incident and exact location. Both fields are filtered for broadcast concurrently, and the caller's exact session and active character are revalidated after that yielding work before a successful request creates an `Immediate` dispatch call. Only one 999 submission may be in flight for an exact Player instance, so a retry or parallel click cannot cross the moderation yield and create duplicate dispatch calls. It never grants the caller MDT access and does not trust the client to set arbitrary dispatch fields.
