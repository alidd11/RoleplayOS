# Characters

Civilian characters and emergency duty profiles are separate. Free and gamepass slot counts are configured. The `CreateCharacter` network boundary accepts only `FirstName`, `LastName` and `DateOfBirth` inside the identity object, then projects those declared fields before passing them to the character service. Creation validates and filters the names, validates the date of birth, assigns a GUID, and generates isolated economy, ownership, employment and inventory state. Selection checks profile ownership and exposes only a character ID; menus use compact summaries. Character selection is serialised per exact Player instance while pending starter-vehicle and cash-drop recovery runs, and it shares the role-transition claim used by duty start and civilian entry. Retries therefore cannot race the active-character pointer, repeat recovery work or overlap a competing team/character transition.

Deletion requires an exact confirmation ID, cannot delete the active character and refuses records with vehicles, properties or employment. A production UI should add a timed confirmation interaction and recovery policy.

The service deletion guard treats any key in a protected collection as a record,
including dictionary or sparse legacy storage. Unreadable protected collections,
present unreadable economy/recovery data and non-table slot state are refused
with `CHARACTER_RECORDS_UNREADABLE` before the character is removed; they are not
rewritten as empty. Pending cash-drop recovery also prevents deletion. This is
a service API contract, not an implementation of the deferred deletion UI.

The avatar creator queries Roblox's catalogue through the server. Category and keyword searches remain bounded and rate-limited, and simultaneous cache misses for the same normalised query share one in-flight catalogue request. Waiting callers reuse the resulting cache entry instead of multiplying pressure on the server-wide Roblox catalogue quota. Distinct cache-miss leaders also pass through a server-wide token bucket, so modified clients cannot multiply that shared external quota by spreading different keywords across many players.

After selection, civilian entry sends only the owned character ID and configured spawn ID. The server confirms the active character, forces the Civilian Team, selects the exact native team pad and respawns. The menu dismisses only after a successful response.
