# Economy

`EconomyService` is the only balance writer. Callers construct a transaction from server configuration; validation rejects non-finite, non-positive, fractional, duplicate and unaffordable operations. The active, owned character is required. Applied transactions update memory atomically, append a bounded history, mark the profile dirty and emit an audit record.

Transactions may select `Account = "Bank"` or `Account = "Cash"`. Omitting the
field continues to mean `Bank`, preserving older callers. Physical money drops
and robbery proceeds use `Cash`; phone transfers, purchases and wages retain
their existing bank behaviour unless their design explicitly says otherwise.

Vehicle, property and furniture services read prices only from configuration. Refund, wage, fine and transfer flows should be added as named EconomyService methods that preserve the same idempotency contract. Never accept a reward or price from a client.

## Wages

Nothing paid anyone. Vehicles, food, furniture and property all took money and only reselling a vehicle ever returned any, so a balance could only fall and every price was arbitrary. Jobs carried a `BaseWage` that no code ever paid out.

Pay now accrues while a shift is worked and is settled on an interval rather than granted in a lump when clocking off, so leaving on a crash or a disconnect costs at most one period. Payments go through the economy service like any other movement of money, so they are validated, recorded in the character's transaction history and audited.

An emergency shift pays by department with a bonus for each rank above the first, so seniority is worth holding. Civilian employment pays less, so the services remain the career path. `BaseWage` on a job is what a completed task is worth and is not treated as an hourly rate; a job may declare an `HourlyRate` of its own.

### Rates are set from prices

The rates in `Config.Payroll` are derived from what things cost, not from what sounds plausible. Against the starter vehicle at fifteen thousand, an emergency shift buys a first car in roughly six hours of play, the premium saloon in about eighteen and the starter flat in about thirty. That leaves the first purchase reachable in a session or two and property a long-term goal.

Change rates and prices together. Raising a price without raising pay lengthens every journey towards it, and the effect compounds across the catalogue.

### Standing still is not working

A character must have covered `MinimumMovementStuds` since the last payment to be paid for it. Without that, a character left standing in a locker room earns exactly as much as one answering calls, which is the fastest way to make every price in the game meaningless. The first period after clocking on is always paid, since there is nothing yet to compare against.

This is a floor rather than a real measure of work. It stops a character being left logged in overnight; it does not stop somebody deliberately walking in circles. Anti-idle evidence tied to actual tasks is the proper answer and belongs with the job adapters.
