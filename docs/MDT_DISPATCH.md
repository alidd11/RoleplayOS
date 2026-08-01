# MDT and dispatch

MDT queries are sanitised, length-limited, rate-limited by the network and paginated. Person results include identity, licences and relevant flags; vehicle results include registration and ownership. Bank, home storage, furniture and unrelated private data are excluded. Every sensitive search is audited.

Incidents and warrants have stable IDs and audit trails. Active units and calls are temporary state. Local updates use RemoteEvents; cross-server hints use small MessagingService events and fail gracefully. Production persistence should convert closed calls into DataStore-backed incidents through DataService and use MemoryStore sorted maps for expiring active snapshots, without polling.
