# Data model

`ProfileSchema` owns version 1 defaults, reconciliation and sequential migrations. Profiles contain settings, character IDs and records, duty profiles, whitelists, applications, qualifications, gamepass cache and audit metadata. Character records own economy, employment, vehicles, properties, furniture, inventory, licences and progression.

All durable references are stable GUID or configuration IDs. Dates are Unix seconds or ISO `YYYY-MM-DD`; transforms are number arrays. Do not persist Roblox values directly. Add migrations before increasing `CURRENT_VERSION`; migrations must be idempotent and tolerate absent fields.

`PlayerProfile.CustodySentence` is deliberately profile-wide so changing character cannot bypass an active custody period. `ReleaseAt` is the authoritative Unix timestamp. `Offences` is a bounded audit summary; offence codes and compressed gameplay durations come only from `Config.Custody.OffenceTariffs`. Character-specific booking and criminal-history entries remain on the selected character. These values simulate game consequences and are not real sentencing guidance.

`DataService` loads once, holds an expiring server ownership lease, caches in memory, tracks dirty state, autosaves, saves on leave, and releases leases at shutdown. UpdateAsync checks ownership before every write. Retries are bounded and back off; unsafe load failure kicks rather than creating a second writable session.
