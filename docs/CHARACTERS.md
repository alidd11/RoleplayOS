# Characters

Civilian characters and emergency duty profiles are separate. Free and gamepass slot counts are configured. Creation validates names and date of birth, assigns a GUID, and generates isolated economy, ownership, employment and inventory state. Selection checks profile ownership and exposes only a character ID; menus use compact summaries.

Deletion requires an exact confirmation ID, cannot delete the active character and refuses records with vehicles, properties or employment. A production UI should add a timed confirmation interaction and recovery policy.

After selection, civilian entry sends only the owned character ID and configured spawn ID. The server confirms the active character, forces the Civilian Team, selects the exact native team pad and respawns. The menu dismisses only after a successful response.
