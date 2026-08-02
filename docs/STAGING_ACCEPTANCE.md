# Staging and live-server acceptance

This is the release gate for **Emergency Response: Portsmouth**. Run it against a separate staging place in the same experience before updating the production start place.

## Build and installation

1. Build the dedicated test place with `rojo build acceptance.project.json -o RoleplayOS-Acceptance.rbxlx`, or serve `acceptance.project.json` to the staging place through the Rojo Studio plugin.
2. Copy the production map into the staging place or synchronise the RoleplayOS tree into a private copy of the real baseplate.
3. Publish the staging place. Enable Studio API access only for controlled Studio testing; published servers use the normal experience DataStores.
4. Never synchronise `tests/` or `acceptance.project.json` into the production start place. The normal `default.project.json` does not contain them.
5. Start a two-client Studio server once for local wiring, then test two published servers concurrently for persistence and isolation.

The Output window must contain both completion messages:

```text
[RoleplayOS Acceptance] Pure contract suite completed
[RoleplayOS Acceptance] COMPLETE | ... | 0 failure(s)
```

Warnings for missing ANPR sensors or dispatch seats mean the map has not been fully tagged. They are not code failures, but must be resolved before release when those systems are in scope.

## Test accounts

Use separate Roblox accounts. Never alter production ranks merely to test.

| Account | Required state |
|---|---|
| A | Member of Universal Projects and all service groups; sufficiently ranked for Control/Roads tests |
| B | Member of Universal Projects; no service-group membership |
| C | Not a member of Universal Projects |
| D | Member of Universal Projects; used in a second live server |

Record usernames, group ranks, place version, JobIds and timestamps in the evidence sheet. Do not record passwords, cookies or security tokens.

## Release acceptance matrix

Mark every row PASS, FAIL or NOT RUN and attach the listed evidence.

| ID | Area | Procedure | Expected result | Evidence |
|---|---|---|---|---|
| GATE-01 | Main group | Join with A and B | Both enter the experience | Server Output and player list |
| GATE-02 | Main group | Join with C | C is denied cleanly without loading a playable character | Screenshot and server audit line |
| GATE-03 | Service ranks | B attempts Armed Response, Roads and Control | Every restricted duty is denied server-side | Response codes |
| GATE-04 | Service ranks | A begins each authorised duty | Correct team, role, spawn and loadout are assigned | Screenshot per duty |
| CHAR-01 | Character | Create a valid character with A | Character appears once and can be selected | UI and response envelope |
| CHAR-02 | Character | Submit empty, oversized and unsuitable identity fields | Rejected or Roblox-filtered; raw text is never persisted/displayed | Response codes and rejoin check |
| DATA-01 | Persistence | Change settings, hunger and selected character; leave cleanly; rejoin another server | Latest values return exactly once | Before/after capture |
| DATA-02 | Lease | Join simultaneously as A from two clients/servers | Only one session owns the profile; no divergent save occurs | Both JobIds and server logs |
| DATA-03 | Shutdown | Change data, then close the server normally | Final revision persists after rejoin | Rejoin capture |
| PLATE-01 | Global registration | Spawn A's starter vehicle, leave and rejoin | Same vehicle has the same registration | Before/after plate capture |
| PLATE-02 | Collision | Generate/spawn vehicles concurrently in two published servers | No two ownership records receive the same registration | Exported audit records |
| PLATE-03 | Custom plate | Submit profanity, impersonation, invalid length and a duplicate | All are rejected/filter-safe; valid unique plate persists | Response codes |
| DEALER-01 | Ownership | New B opens dealership | Exactly one configured starter vehicle is owned | Vehicle menu capture |
| DEALER-02 | Purchase | Buy a vehicle with insufficient and sufficient funds | Server price is authoritative; one debit and one ownership record | Balance/ownership before and after |
| DEALER-03 | Spawn | Spam spawn and obstruct the bay | Rate limit/clearance blocks abuse; at most one active vehicle | Output and world capture |
| SERVICE-01 | Team vehicles | B requests restricted service vehicles | Denied regardless of client payload | Response code |
| SERVICE-02 | Team vehicles | A requests each rank-eligible vehicle while on/off matching duty | Allowed only on matching duty and configured rank | Matrix of results |
| DISP-01 | Seat | A sits in tagged dispatch `Seat` and `VehicleSeat` test fixtures | Dispatch opens only for a tagged dispatch console, never an ordinary vehicle seat | Video/capture |
| DISP-02 | Call creation | A creates and edits a call | Filtered call appears with correct priority, department and JobId | Dispatch and Output |
| DISP-03 | Scope | Police, Ambulance and Control clients observe a Police-only call | Police and Control see it; Ambulance does not | Three-client capture |
| DISP-04 | Assignment | Dispatcher assigns incompatible then compatible units | Incompatible assignment is denied; compatible assignment succeeds once | Response codes |
| MDT-01 | Authorisation | B invokes every MDT endpoint directly | Server denies all restricted actions | Response codes |
| MDT-02 | Records | A searches person, vehicle, warrant and custody data after a rejoin | Persistent indexed records are returned and scoped | MDT captures |
| ANPR-01 | Wanted hit | Mark a vehicle wanted and drive it through tagged ANPR | One call/alert reaches Roads Policing and Control | Alert/call captures |
| ANPR-02 | Scope | Frontline-only and unrelated service clients observe the hit | No ANPR popup is sent to unauthorised clients | Client captures |
| ANPR-03 | Cooldown | Pass the same sensor repeatedly inside cooldown | One alert/call only; later pass after cooldown may alert again | Call IDs and timestamps |
| CUST-01 | Arrest | Equipped authorised A cuffs nearby B | B is restrained; distance, target and state are server-validated | Two-client video |
| CUST-02 | Booking | Transport B to custody and complete booking | Persistent record uses selected character and filtered reason | Rejoin and MDT capture |
| CUST-03 | Abuse | Attempt remote cuff/book from far away, wrong duty or without tool | Every attempt is denied with no state change | Response codes |
| PHONE-01 | Text/call | A and B exchange a message and call | Text is filtered, server-local recipient is correct, call states clean up | Two-client capture |
| PHONE-02 | Emergency | B calls 999 | A server-local emergency call is created with caller number/name and correct departments | Phone and dispatch captures |
| PHONE-03 | Isolation | D is in a second JobId while B calls/texts/999 | D receives no call, text, contact or dispatch payload from the first server | Both JobIds and captures |
| NEED-01 | Sprint | Sprint until empty, stop, recover and attempt while seated/cuffed | Speed degrades/recoveries correctly and invalid states cannot sprint | Video and humanoid properties |
| NEED-02 | Hunger | Drain/buy food/rejoin | Purchase is authoritative and hunger persists | Before/after capture |
| NEED-03 | Network rate | Observe `NeedsChanged` for 60 seconds idle and moving | Events are change-based, no more than two per second per player | MicroProfiler/network capture |
| UI-01 | UI states | Test on foot, driver, passenger, dispatch seat, phone and modal | No overlap with Roblox top bar, hotbar or vehicle controls | Captures at target resolutions |
| UI-02 | Devices | Test 1920x1080, 1366x768, tablet and phone emulation | Controls remain readable/tappable and safe-area aware | Device emulator captures |
| SEC-01 | Payloads | Send oversized, cyclic-equivalent, wrong-type and rapid requests | Payload/rate limits reject safely without server errors | Response codes and Output |
| ISO-01 | Server boundary | Run calls, ANPR, texts and dispatch changes in Server 1 | Server 2 receives none; all payload JobIds match their origin | Dual-server evidence |

## Performance gate

Test with the intended maximum player count or the closest practical Studio simulation.

- No repeating errors or warnings after the initial acceptance report.
- Server frame time remains stable while driving through streamed areas.
- Script activity has no unexplained continuous high-frequency task.
- Network receive/send does not grow continuously while players are idle.
- Memory reaches a stable plateau after repeated spawn/despawn, duty and phone cycles.
- A player owns at most one active spawned vehicle.
- Imported assets contain no scripts, remotes or bindables; the automated runtime check enforces this for `RoleplayOSAssets`.

Capture the MicroProfiler, Developer Console server/client memory, network graphs and final Output log.

## Release decision

Release only when:

1. Both automated suites report zero failures.
2. Every `GATE`, `DATA`, `PLATE`, `DISP`, `ANPR`, `CUST`, `PHONE`, `SEC` and `ISO` row passes.
3. Any NOT RUN row has a named owner and explicit written risk acceptance.
4. The tested place version is the exact version promoted to production.

Rollback immediately if published production shows profile lease conflicts, duplicate registrations, cross-server information leakage, unfiltered text, unrestricted duties, repeating errors or unbounded resource growth.
