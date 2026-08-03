# Mobile phone

RoleplayOS Mobile is an original modern smartphone interface rather than a copy of a branded handset. It is taken out by selecting the Phone tool in the toolbar, the way a handset is taken from a pocket, or with the `P` key; putting the tool away closes it. There is no on-screen launcher, so nothing competes with the rest of the interface for a corner of the screen. The handset uses the selected civilian character's persistent phone identity.

Its home screen is a grid of apps with a dock of pinned ones, and the heading and dock give way to whichever app is open. A wallet app shows the holder's own identity card. Reading your own card is not the same as presenting it: showing identification to another player still goes through the identification service, which requires the physical card in hand and the other player within range.

It also exists as a held toolbar `Tool` with a welded screen and a server-controlled flashlight. The home screen uses an icon dock and includes a Contacts app showing active characters in this server.

Each character receives a stable UK-format mobile number. Players in the same live server can call by number, answer, connect and end a call. The call service is server-authoritative and prevents self-calls, double calls and answering another player's call. Call signalling works for every player. Private audio routing must only be enabled after the experience accepts Roblox's Chat & Voice Groups API terms and enables `VoiceChatService.UseAudioApi`; ordinary proximity voice is not presented as a private phone channel.

Texts are length-limited, rate-limited and filtered through Roblox `TextService` before either participant sees or stores them. Messages are capped per character to bound profile size. The current implementation intentionally supports online recipients in the same server; reliable offline or cross-server delivery needs a dedicated indexed message store rather than writing into another server's session-locked profile.

The 999 page asks for an incident and exact location. Both fields are filtered for broadcast, and a successful request creates an `Immediate` dispatch call. It never grants the caller MDT access and does not trust the client to set arbitrary dispatch fields.
