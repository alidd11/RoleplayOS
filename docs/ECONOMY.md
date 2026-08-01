# Economy

`EconomyService` is the only balance writer. Callers construct a transaction from server configuration; validation rejects non-finite, non-positive, fractional, duplicate and unaffordable operations. The active, owned character is required. Applied transactions update memory atomically, append a bounded history, mark the profile dirty and emit an audit record.

Vehicle, property and furniture services read prices only from configuration. Refund, wage, fine and transfer flows should be added as named EconomyService methods that preserve the same idempotency contract. Never accept a reward or price from a client.
