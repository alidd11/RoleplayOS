# Characters

Civilian characters and emergency duty profiles are separate. Free and gamepass slot counts are configured. The `CreateCharacter` network boundary accepts only `FirstName`, `LastName` and `DateOfBirth` inside the identity object, then projects those declared fields before passing them to the character service. Creation validates and filters the names, validates the date of birth, assigns a GUID, and generates isolated economy, ownership, employment and inventory state. Selection checks profile ownership and exposes only a character ID; menus use compact summaries.

Deletion requires an exact confirmation ID, cannot delete the active character and refuses records with vehicles, properties or employment. A production UI should add a timed confirmation interaction and recovery policy.

The avatar creator queries Roblox's catalogue through the server. Category and keyword searches remain bounded and rate-limited, and simultaneous cache misses for the same normalised query share one in-flight catalogue request. Waiting callers reuse the resulting cache entry instead of multiplying pressure on the server-wide Roblox catalogue quota.

After selection, civilian entry sends only the owned character ID and configured spawn ID. The server confirms the active character, forces the Civilian Team, selects the exact native team pad and respawns. The menu dismisses only after a successful response.
