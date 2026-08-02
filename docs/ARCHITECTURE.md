# Architecture

The bootstrap validates configuration, constructs one shared context, explicitly registers services in dependency order, then performs two phases: every `Init` must succeed before any `Start` runs. Required failures abort startup; optional cross-server integrations report degraded operation. Shutdown destroys services in reverse order.

The context exposes the logger, immutable configuration, network gateway and service registry. Services obtain peers from the registry and must not require one another, preventing module cycles. Shared modules are dependency-free pure logic where practical.

Data flows from a validated client request into one domain service. That service re-evaluates access and ownership, obtains server-defined content and prices, mutates the in-memory profile through the relevant authority, marks it dirty, and writes an audit event. `DataService` batches persistence. Response DTOs contain only required fields.

Persistent profile state and the bounded MDT operational projection live in DataStore. Per-server sessions, active shifts, units, calls, spawned vehicles and interiors remain runtime state. Dispatch uses local events only: active call data is deliberately never placed on MessagingService or another cross-server transport. Closing a call may create a durable historical incident, but it does not replicate the active queue.
