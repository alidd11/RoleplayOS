# Economy

`EconomyService` is the only balance writer. Callers construct a transaction from server configuration; validation rejects non-finite, non-positive, fractional, duplicate and unaffordable operations. The active, owned character is required. Applied transactions update memory atomically, append a bounded history, mark the profile dirty and emit an audit record.

Transactions may select `Account = "Bank"` or `Account = "Cash"`. Omitting the
field continues to mean `Bank`, preserving older callers. Physical money drops
and robbery proceeds use `Cash`; phone transfers, purchases and wages retain
their existing bank behaviour unless their design explicitly says otherwise.

Replay protection is rebuilt from each character's persisted bounded transaction
history when a server takes ownership of the profile. Recovery operations that
may be retried must therefore use a deterministic transaction ID. Pending player
transfer refunds derive that ID from the transfer, save the profile before
retiring the pending item, and persist a reconciled receipt so a stale shared
index entry cannot credit the same refund again. New refund recovery entries keep
the recovery payload in the discoverable shared index itself, so creating a
recoverable debt is one atomic shared-record update rather than a record write
followed by an index write that could orphan the debt. Legacy string index entries
remain readable until they reconcile and drain naturally.

Cash drops use the same recovery rule. Normal expiry still removes uncollected
cash, but drops do not outlive the profile session that paid for them: leaving
the server or an orderly shutdown removes the world drop and refunds it. If the
owning character is not active, the refund is kept in that character's
`PendingCashDropRefunds` profile container instead. Character selection
reconciles those entries through EconomyService using deterministic transaction
IDs and removes them in the same profile mutation. The container is bounded by
the per-player active-drop limit for each character, so recovery cannot grow
into a global persistent queue.

Vehicle, property and furniture services read prices only from configuration. Refund, wage, fine and transfer flows should be added as named EconomyService methods that preserve the same idempotency contract. Taxi fares use `EconomyService:PayTaxiFare()`, so journey validation stays in TaxiService while the two-player balance mutation, transfer lock, refund recovery and immediate persistence stay in EconomyService. TaxiService claims an accepted request while that yielding settlement is in flight, so completion retries and cancellation cannot race the same fare; a participant disconnecting during a failed settlement releases the booking after the settlement returns. Cancellation is terminal: retained `Cancelled` requests cannot be replayed to refresh their retention timestamp or resend status notifications. Never accept a reward or price from a client.

## Wages

Nothing paid anyone. Vehicles, food, furniture and property all took money and only reselling a vehicle ever returned any, so a balance could only fall and every price was arbitrary. Jobs carried a `BaseWage` that no code ever paid out.

Pay now accrues while a shift is worked and is settled on an interval rather than granted in a lump when clocking off, so leaving on a crash or a disconnect costs at most one period. Payments go through the economy service like any other movement of money, so they are validated, recorded in the character's transaction history and audited. Duty/access resolution can yield on Roblox group checks; payroll therefore revalidates its own runtime, the exact Player and the current character session after that boundary before movement state or wages are touched.

An emergency shift pays by department with a bonus for each rank above the first, so seniority is worth holding. Civilian employment pays less, so the services remain the career path. `BaseWage` on a job is what a completed task is worth and is not treated as an hourly rate; a job may declare an `HourlyRate` of its own.

### Rates are set from prices

The rates in `Config.Payroll` are derived from what things cost, not from what sounds plausible. Against the starter vehicle at fifteen thousand, an emergency shift buys a first car in roughly six hours of play, the premium saloon in about eighteen and the starter flat in about thirty. That leaves the first purchase reachable in a session or two and property a long-term goal.

Change rates and prices together. Raising a price without raising pay lengthens every journey towards it, and the effect compounds across the catalogue.

### Standing still is not working

A character must have covered `MinimumMovementStuds` since the last payment to be paid for it. Without that, a character left standing in a locker room earns exactly as much as one answering calls, which is the fastest way to make every price in the game meaningless. The first period after clocking on is always paid, since there is nothing yet to compare against.

This is a floor rather than a real measure of work. It stops a character being left logged in overnight; it does not stop somebody deliberately walking in circles. Anti-idle evidence tied to actual tasks is the proper answer and belongs with the job adapters.
