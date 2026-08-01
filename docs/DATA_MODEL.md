# Data model

`ProfileSchema` owns version 1 defaults, reconciliation and sequential migrations. Profiles contain settings, character IDs and records, duty profiles, whitelists, applications, qualifications, gamepass cache and audit metadata. Character records own economy, employment, vehicles, properties, furniture, inventory, licences and progression.

All durable references are stable GUID or configuration IDs. Dates are Unix seconds or ISO `YYYY-MM-DD`; transforms are number arrays. Do not persist Roblox values directly. Add migrations before increasing `CURRENT_VERSION`; migrations must be idempotent and tolerate absent fields.

`DataService` loads once, holds an expiring server ownership lease, caches in memory, tracks dirty state, autosaves, saves on leave, and releases leases at shutdown. UpdateAsync checks ownership before every write. Retries are bounded and back off; unsafe load failure kicks rather than creating a second writable session.
