# MDT persistence and offline search

MDT searches are server-authorised and operate on durable, filtered record snapshots. They do not scan the live `Players` list and do not call `ListKeysAsync()` during an interactive search.

## Stores

- `RoleplayOS_MDTRecords_v1` stores person records by stable character ID and vehicle records by stable vehicle ID.
- `RoleplayOS_MDTIndexes_v1` stores bounded two-character buckets for filtered first/last-name tokens and normalised registrations.
- Player profiles remain authoritative for player-owned economy and gameplay state. MDT snapshots are an operational projection, updated idempotently after character, vehicle, custody and road-safety mutations.

Index writes use `UpdateAsync()` through the same bounded retry layer as the rest of RoleplayOS. Gameplay mutations schedule and coalesce projection work rather than waiting on DataStore latency. Existing profiles are indexed in a spaced background queue when their owner joins. Each bucket has a configured maximum and evicts its oldest entry if that hard bound is reached.

## Warrants

Warrants live inside the durable person record rather than server memory. Creation and revocation require the `WarrantWrite` MDT permission, filter the supplied reason, validate the expiry, use stable request-generated warrant IDs, and write an audit event. Repeated `UpdateAsync()` transforms do not duplicate a warrant.

Active warrants appear as `WANTED` flags in both person and registered-vehicle results. The MDT exposes issue and two-step revoke controls only to authorised duties.

## Failure behaviour

If the record or index store is unavailable, the MDT returns an unavailable response instead of silently presenting an incomplete online-only result. The underlying profile mutation remains marked for persistence and a later join rebuilds its operational projection. Production acceptance must still exercise throttling, ambiguous writes, offline searches and concurrent servers in a published staging place.
