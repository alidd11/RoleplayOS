# MDT persistence and offline search

MDT searches are server-authorised and operate on durable, filtered record snapshots. They do not scan the live `Players` list and do not call `ListKeysAsync()` during an interactive search.

Person and vehicle searches derive the search permission, department access profile and warrant visibility from one exact authorised duty snapshot. Because index and record reads can yield, the same duty snapshot is revalidated before successful results are returned; a duty/role change or disconnect during persistence causes the response to be rejected instead of leaking records authorised by stale state.

## Stores

- `RoleplayOS_MDTRecords_v1` stores person records by stable character ID and vehicle records by stable vehicle ID.
- `RoleplayOS_MDTIndexes_v1` stores bounded two-character buckets for filtered first/last-name tokens and normalised registrations.
- Player profiles remain authoritative for player-owned economy and gameplay state. MDT snapshots are an operational projection, updated idempotently after character, vehicle, custody and road-safety mutations.

Index writes use `UpdateAsync()` through the same bounded retry layer as the rest of RoleplayOS. Gameplay mutations schedule and coalesce projection work rather than waiting on DataStore latency. Existing profiles are indexed in a spaced background queue when their owner joins. Each bucket has a configured maximum and evicts its oldest entry if that hard bound is reached. Registration changes treat removal of the previous vehicle-search bucket as part of the projection result rather than silently ignoring a failed cleanup. Vehicle searches also validate each indexed registration against the current durable vehicle record and suppress/retry removal of stale old-plate entries instead of returning a vehicle under a registration it no longer owns.

Closed dispatch calls are projected in two durable steps: the incident record first, then the bounded recent-incidents index. A resolved call remains the bounded recovery source for the configured active-state TTL. If the primary record succeeds but the index exhausts its own DataStore retries, later recovery attempts repair only the index rather than rewriting the record. The existing call sweep retries at the configured incident-persistence cadence, and orderly shutdown makes one final projection attempt before CallService releases its runtime calls.

Incident creation requires `IncidentWrite` both before and after title filtering. The department recorded on the incident comes from the post-filter authorised duty snapshot, so a request that lost duty, role permission or its live player session while moderation yielded is rejected before persistence.

Manual incident closure performs one authoritative record update and then projects that committed record to the recent-incidents index. Closing an already-closed incident is idempotent: retries preserve the original closure actor, timestamp and revision, allowing a failed index projection to be repaired without rewriting closure history.

Incident history reads authorise `IncidentRead` or `IncidentWrite` inside `IncidentService`, then revalidate the exact same duty snapshot after any index/record DataStore reads have completed. A player who leaves duty, changes role or disconnects while persistence is yielding receives no incident records, and the network endpoint does not spend a separate duplicate permission lookup.

## Warrants

Warrants live inside the durable person record rather than server memory. Creation and revocation require the `WarrantWrite` MDT permission, filter the supplied reason, validate the expiry, use stable request-generated warrant IDs, and write an audit event. Because reason filtering can yield, creation revalidates the officer's current `WarrantWrite` authority immediately before the durable write. Repeated `UpdateAsync()` transforms do not duplicate a warrant. Revocation also carries a per-operation marker through `UpdateAsync` retries: discarded conflict transforms cannot leak stale revoker attribution, while an ambiguous retry can recognise a revocation already committed by that same operation without claiming another server's change.

Active warrants appear as `WANTED` flags in both person and registered-vehicle results. The MDT exposes issue and two-step revoke controls only to authorised duties. Vehicle searches that are authorised to expose warrant flags fail closed if the owner person record cannot be read, rather than presenting a temporary record-store failure as a clean vehicle. The server-side warrant lookup cache is TTL-bound and capped by `MaximumWarrantCacheCharacters`; ANPR misses read through the durable person record before deciding that a vehicle is not wanted, so cache eviction does not create false clean results.

## Failure behaviour

If the record or index store is unavailable, the MDT returns an unavailable response instead of silently presenting an incomplete online-only result. The underlying profile mutation remains marked for persistence and a later join rebuilds its operational projection. Production acceptance must still exercise throttling, ambiguous writes, offline searches and concurrent servers in a published staging place.
