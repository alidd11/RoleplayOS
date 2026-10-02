# Data model

`ProfileSchema` owns version 1 defaults, reconciliation and sequential migrations. Profiles contain settings, character IDs and records, duty profiles, whitelists, applications, qualifications, gamepass cache and audit metadata. Character records own economy, employment, vehicles, properties, furniture, inventory, licences and progression.

All durable references are stable GUID or configuration IDs. Dates are Unix seconds or ISO `YYYY-MM-DD`; transforms are number arrays. Do not persist Roblox values directly. Add migrations before increasing `CURRENT_VERSION`; migrations must be idempotent and tolerate absent fields. Missing legacy authoritative values may be backfilled, but present values that cannot be interpreted safely must fail migration so DataService can preserve and quarantine the original profile instead of committing a destructive default.

Stored schema versions must identify a finite, non-negative integer migration step. Finite legacy numeric strings remain readable; negative/fractional versions and non-finite authoritative migration values are rejected. Overflowed numeric strings are non-finite too. Future integer versions still return `PROFILE_VERSION_TOO_NEW`, preserving rollback protection. These corruption guards do not change the schema version or valid-profile rounding rules.

Inventory quantities are positive finite integers. Containers must be dense lists
with consecutive positive integer keys, not dictionaries or sparse arrays. Shape
is checked before any quantity mutation. Stack caps apply to both new and existing
grants. InventoryService may backfill a missing legacy container,
but refuses a present unreadable container or matching unreadable quantity without
mutating or dirtying it. Unrelated malformed rows are preserved and ignored by
item lookup; they are not automatically deleted. `Has` exposes only usable
quantities. These guards do not repair corrupted ownership or change the schema.

`PlayerProfile.CustodySentence` is deliberately profile-wide so changing character cannot bypass an active custody period. `ReleaseAt` is the authoritative Unix timestamp. `Offences` is a bounded audit summary; offence codes and compressed gameplay durations come only from `Config.Custody.OffenceTariffs`. Character-specific booking and criminal-history entries remain on the selected character. These values simulate game consequences and are not real sentencing guidance.

`DataService` loads once, holds an expiring server ownership lease, caches in memory, tracks dirty state, autosaves, saves on leave, and releases leases at shutdown. Autosave launches are spread across only part of each cadence so DataStore pressure is smoothed without stretching a profile's lease-renewal interval up to the lease expiry. Loaded profiles establish a size baseline, and dirty snapshots are measured again before ordinary saves so long-session growth reaches the configured warning before Roblox's DataStore value ceiling; the extra encode is skipped during server shutdown to protect the bounded final-save window. UpdateAsync checks ownership before every write. Retries are bounded and back off; unsafe load failure kicks rather than creating a second writable session.

Startup validation rejects non-finite persistence timings, retry counts and
present optional wait/size guards. Retry counts are positive whole numbers;
absent optional fields retain their runtime fallbacks, and a zero maximum lease
wait still permits immediate refusal. Existing lease/cadence relationships and
the profile-warning threshold below the storage ceiling remain enforced.

Public and official-whitelisted progression are separate persistence domains. Existing public profiles retain the historical bare `UserId` key. Official reserved-server profiles use `wl:<OfficialServerId>:<UserId>`, and the same namespace is applied to MDT projections and indexes, custom-registration reservations and shoulder-number allocations. Shared gang progression uses the equivalent DataStore scope `wl:<OfficialServerId>`: public gang records keep their historical global keys, while official gang membership, unique-name reservations and territory ownership live in the official scope. This prevents public money, vehicles, records, service identity and gang territory income from carrying into an official session even though both modes run inside the same Portsmouth place. The community and official-server directory remains globally shared because it is routing/configuration data rather than player progression. Development in a separate universe is isolated by Roblox itself; Studio mock profiles remain memory-only.
