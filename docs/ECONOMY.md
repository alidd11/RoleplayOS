# Economy

`EconomyService` is the only balance writer. Callers construct a transaction from server configuration; validation rejects non-finite, non-positive, fractional, duplicate and unaffordable operations. The active, owned character is required. Applied transactions update memory atomically, append a bounded history, mark the profile dirty and emit an audit record.

Startup requires `MaximumTransactionHistory` and `MaximumTransferReceipts` to be
finite whole numbers of at least one. Infinity cannot disable retention by
passing the integer check. Existing cap defaults and valid finite tuning are
unchanged; invalid configuration is refused before services start.

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
remain readable until they reconcile and drain naturally. Refund reconciliation
runs against the selected character rather than merely the loaded profile: profile
load precedes character selection, so attempting recovery at load time has no
authoritative character to credit. A short player-join watcher provides a second
bounded attempt after selection without creating an unbounded retry task.

Two-profile transfers use a separate write-ahead settlement protocol. A transfer
first reserves one pending pointer in each participant's shared record, then writes
the full `Committed` settlement record before either balance is mutated. A crash
before that record exists leaves pointers that recovery can safely clear because no
balance has changed. A selected participant replays only their own deterministic
debit or credit transaction, saves their profile, and acknowledges that leg. The
other leg can be recovered when that participant next selects the character. Both
characters remain blocked from economy mutations while their pending pointers
exist, so a failed save cannot be followed by spending against a half-settled
balance. Once both profile saves are acknowledged, the sender receives a bounded
receipt and both pending pointers are removed. The pending state is structurally
limited to one settlement per player; completed sender receipts are bounded by
`Economy.MaximumTransferReceipts`.

Receipt retention treats missing, non-numeric and non-finite completion timestamps
as unknown chronology (oldest), with the existing ID tie-break. The current
receipt remains protected by the retention ordering. This fallback does not
rewrite historical replay payloads: malformed scalar rows are removed, but a
receipt table is only evicted when the configured cap requires it. Corrupt
timestamp metadata must not prevent a committed settlement from finalising.

Committed records are never rolled back; each profile's deterministic transaction ID makes replay safe
when a save or acknowledgement result was ambiguous. Phone transfer attempts carry
a stable operation ID across timeouts, and taxi fares derive their settlement ID
from the taxi request ID.

New pending transfer refunds are stored in a player-scoped shared recovery record
rather than appended to the legacy global index. Once a character has unresolved
recovery, further outgoing transfers from that character are refused until the
record reconciles, preventing a persistence outage from growing an unbounded debt
queue. The old global index is read only for compatibility and drains as historical
entries reconcile; new failures never append to it.

Cash drops use the same recovery rule. Normal expiry still removes uncollected
cash, but drops do not outlive the profile session that paid for them: leaving
the server or an orderly shutdown removes the world drop and refunds it. If the
owning character is not active, the refund is kept in that character's
`PendingCashDropRefunds` profile container instead. Character selection
reconciles those entries through EconomyService using deterministic transaction
IDs and removes them in the same profile mutation. The container is bounded by
the per-player active-drop limit for each character, so recovery cannot grow
into a global persistent queue.

Vehicle, property and furniture services read prices only from configuration. Refund, wage, fine and transfer flows should be added as named EconomyService methods that preserve the same idempotency contract. Taxi fares use `EconomyService:PayTaxiFare()`, so journey validation stays in TaxiService while the two-player balance mutation, transfer lock, refund recovery and immediate persistence stay in EconomyService. TaxiService claims an accepted request while that yielding settlement is in flight, so completion retries and cancellation cannot race the same fare.

If a fare result is ambiguous or recoverable after a validated journey, the request remains settlement-pending and cannot be cancelled. Completion retries reuse the taxi request ID and skip the journey checks, but still require the original active characters. Only definitive insufficient-funds or invalid-fare responses clear that pending state and make the request cancellable. A participant disconnecting during settlement cannot turn a possibly committed fare into a cancelled request. Pending taxi request metadata is bounded by the terminal-request cap and request-retention period; pruning that in-memory booking does not delete the EconomyService settlement journal, which still recovers on character selection. Cancellation is terminal: retained `Cancelled` requests cannot be replayed to refresh their retention timestamp or resend status notifications. Never accept a reward or price from a client.

## Custody release credits

Public custody release consumes one early-release credit. Character loading can
yield while a developer receipt grants additional credits to the same profile.
If release is refused, only the attempted credit is returned to the current
count; the refund must not overwrite a concurrent grant. Successful release
notifications report the current count. This preserves the receipt replay marker
and does not change product IDs, prices, grant quantities or sentence policy.

## Appearance edit credits

A paid appearance edit consumes one credit only after avatar application succeeds
and the exact player, session and character remain current. Avatar application
can yield while a developer receipt grants another credit, so the successful edit
deducts from the current count. Failed applications consume no credit. Free first
edits, prices and product grant quantities retain their existing behaviour.

## Wages

Nothing paid anyone. Vehicles, food, furniture and property all took money and only reselling a vehicle ever returned any, so a balance could only fall and every price was arbitrary. Jobs carried a `BaseWage` that no code ever paid out.

Pay now accrues while a shift is worked and is settled on an interval rather than granted in a lump when clocking off, so leaving on a crash or a disconnect costs at most one period. Payments go through the economy service like any other movement of money, so they are validated, recorded in the character's transaction history and audited. Duty/access resolution can yield on Roblox group checks; payroll therefore revalidates its own runtime, the exact Player and the current character session after that boundary before movement state or wages are touched.

An emergency shift pays by department with a bonus for each rank above the first, so seniority is worth holding. Civilian employment pays less, so the services remain the career path. `BaseWage` on a job is what a completed task is worth and is not treated as an hourly rate; a job may declare an `HourlyRate` of its own.

Civilian payroll selects the newest readable employment row with a configured
job. Malformed scalar rows and unknown jobs are ignored without deleting or
rewriting the persisted history. If no usable job remains, no civilian wage is
paid and its movement mark is cleared. This is a read guard, not a schema repair
or a change to wage rates. The worker's existing per-player error boundary keeps
one player's failure from stopping payments for other players.

### Rates are set from prices

The rates in `Config.Payroll` are derived from what things cost, not from what sounds plausible. Against the starter vehicle at fifteen thousand, an emergency shift buys a first car in roughly six hours of play, the premium saloon in about eighteen and the starter flat in about thirty. That leaves the first purchase reachable in a session or two and property a long-term goal.

Change rates and prices together. Raising a price without raising pay lengthens every journey towards it, and the effect compounds across the catalogue.

### Standing still is not working

A character must have covered `MinimumMovementStuds` since the last payment to be paid for it. Without that, a character left standing in a locker room earns exactly as much as one answering calls, which is the fastest way to make every price in the game meaningless. The first period after clocking on is always paid, since there is nothing yet to compare against.

This is a floor rather than a real measure of work. It stops a character being left logged in overnight; it does not stop somebody deliberately walking in circles. Anti-idle evidence tied to actual tasks is the proper answer and belongs with the job adapters.
