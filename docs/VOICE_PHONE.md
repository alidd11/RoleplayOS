# In-game phone voice

RoleplayOS uses Roblox's modern Audio API as the free voice transport. No external voice provider is required.

When a recipient answers, `PhoneVoiceService` connects the caller's `AudioDeviceInput` directly to an `AudioDeviceOutput` assigned to the recipient, and creates the reverse route. These are non-spatial device routes, so distance in the world does not reduce phone volume. Routes exist only for an accepted call and are destroyed on hang-up, player departure or service shutdown.

Each direction passes through a lightweight `AudioEqualizer` with a modest telephone-band curve. This keeps speech clear while making the call route audibly distinct from nearby proximity voice; no uploaded audio asset or paid external service is involved.

## Required experience settings

- The place must be published with voice chat available.
- Maximum players must remain within Roblox voice-chat limits.
- `VoiceChatService.UseAudioApi` must be Enabled in Studio and the place republished.
- Players must individually satisfy Roblox voice eligibility and enable voice.

Roblox may not create an `AudioDeviceInput` for an ineligible or voice-disabled player. RoleplayOS treats voice as optional: the call UI stays connected and returns `VOICE_NOT_AVAILABLE` rather than failing the entire phone call.

Normal proximity voice can remain enabled. A nearby caller may therefore also be audible spatially; the direct phone route supplies the distance-independent call path. A future fully custom voice graph can replace default proximity routing if the experience needs separate equalisation, sidetone or radio effects.

## Safety boundaries

- The client cannot select arbitrary audio inputs, outputs or recipients.
- The server creates routes only after the intended recipient accepts the existing call ID.
- Existing phone endpoint rate limits protect signalling.
- No voice is recorded or persisted by RoleplayOS.
- Text and 999 workflows remain available without voice.

Official references:

- [Roblox voice chat](https://create.roblox.com/docs/chat/voice-chat)
- [Add voice chat](https://create.roblox.com/docs/tutorials/use-case-tutorials/audio/add-voice-chat)
- [AudioDeviceInput](https://create.roblox.com/docs/reference/engine/classes/AudioDeviceInput)
- [AudioDeviceOutput](https://create.roblox.com/docs/reference/engine/classes/AudioDeviceOutput)
- [Wire](https://create.roblox.com/docs/reference/engine/classes/Wire)
