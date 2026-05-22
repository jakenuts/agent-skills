# Durability: Inbox, Outbox, Idempotency, DLQ

How to guarantee that messages aren't lost, duplicated, or applied out of
order relative to your database writes — **without** distributed transactions.

## Contents

- [Mental model](#mental-model)
- [Picking a message store](#picking-a-message-store)
- [Outbox: making outgoing messages durable](#outbox)
- [Inbox: making incoming messages durable](#inbox)
- [Transactional middleware](#transactional-middleware)
- [Idempotency](#idempotency)
- [Dead letter storage](#dead-letter-storage)
- [Claim checks (large messages)](#claim-checks)
- [Stale message recovery](#stale-message-recovery)
- [Message identity (for modular monoliths)](#message-identity-for-modular-monoliths)
- [Operating the durability subsystem](#operating-the-durability-subsystem)

## Mental model

```
                +-----------+    same transaction    +------------+
client  ---->  | listener  | ---------------------> |  inbox     |
                +-----------+                        +------------+
                      |
                      v
                +-----------+    same transaction    +------------+
                | handler   | ---------------------> | DB writes  |
                +-----------+                        |   +        |
                                                     |  outbox    |
                                                     +------------+
                                                            |
                                                            v
                                                  (async relay to brokers)
```

Wolverine never uses two-phase commit. Instead, it stores outgoing envelopes
**in the same database transaction** as your business writes; a background
agent then forwards them to the configured transports. On the inbound side,
the listener writes the envelope to the inbox in a single transaction so
re-deliveries are deduplicated.

Stores: Marten (Postgres), EF Core (Postgres / SQL Server), RavenDb. Persistence
is per-application — multi-tenant variants distribute across tenant DBs.

## Picking a message store

| Store / persistence | Use when |
|---|---|
| `opts.PersistMessagesWithPostgresql(cs, schema)` | EF Core or no ORM, Postgres |
| `opts.PersistMessagesWithSqlServer(cs, schema)` | EF Core or no ORM, SQL Server |
| Marten via `opts.IntegrateWithWolverine()` in `AddMarten` | You're already using Marten |
| EF Core via `opts.UseEntityFrameworkCoreTransactions()` | You have a `DbContext` per service |
| RavenDb via `opts.UseRavenDbPersistence()` | RavenDb store |

See [persistence.md](persistence.md) for full Marten / EF Core / RavenDb
wiring.

## Outbox

Mark which outgoing endpoints should be durable:

```csharp
// per endpoint
opts.PublishMessage<OrderPlaced>().ToRabbitExchange("events").UseDurableOutbox();

// global policy
opts.Policies.UseDurableOutboxOnAllSendingEndpoints();
```

**Without** transactional middleware (long-hand, Marten):

```csharp
public static async Task Handle(CreateOrder cmd,
    IDocumentSession session, IMartenOutbox outbox, CancellationToken ct)
{
    var order = new Order { Description = cmd.Description };
    session.Store(order);
    await outbox.SendAsync(new OrderCreated(order.Id));
    await session.SaveChangesAsync(ct);   // writes order + envelope atomically
}
```

`outbox.SendAsync(...)` only **stages** the message — it ships after the
session commit. Same idea for EF Core via `IDbContextOutbox`.

## Inbox

```csharp
opts.ListenToRabbitQueue("orders").UseDurableInbox();
// or
opts.Policies.UseDurableInboxOnAllListeners();
```

For local queues:

```csharp
opts.Policies.UseDurableLocalQueues();
// or selectively
opts.LocalQueue("important").UseDurableInbox();
```

Local queues that are not durable lose pending messages on a crash.

## Transactional middleware

If your handler injects `IDocumentSession` (Marten) or a `DbContext` (EF Core),
the transactional middleware will:

- Open / share the session/transaction.
- Stage cascaded messages into the outbox.
- Commit at the end of the handler.
- Send the staged messages.

Enable per-handler with `[Transactional]`, or globally:

```csharp
opts.Policies.AutoApplyTransactions();
```

Now this handler is correct without any explicit `SaveChangesAsync` — works
identically for Marten and EF Core. Wolverine opens the transaction, injects
the session/`DbContext`, intercepts your returned events into the outbox,
commits once, then ships the staged messages:

```csharp
// Marten
public static OrderCreated Handle(CreateOrder cmd, IDocumentSession session)
{
    var order = new Order { Description = cmd.Description };
    session.Store(order);
    return new OrderCreated(order.Id);    // staged in outbox, sent on commit
}

// EF Core — same shape, different session type
public static OrderCreated Handle(CreateOrder cmd, AppDbContext db)
{
    var order = new Order { Description = cmd.Description };
    db.Orders.Add(order);
    return new OrderCreated(order.Id);    // staged in outbox, sent on SaveChanges
}
```

> ⚠️ **Don't call `SaveChangesAsync` yourself when transactional middleware
> is in effect.** The middleware commits at the end of the handler. A manual
> `SaveChangesAsync` produces a second commit and the outbox staging that
> Wolverine added after your return value is committed in a different
> transaction from your business writes — defeating the entire point.

## Idempotency

Wolverine's inbox already deduplicates by envelope `Id`. For application-level
idempotency (re-running a command produces the same result), set message IDs
deterministically — Wolverine treats a re-submitted envelope with a matching
`Id` as already processed.

```csharp
await bus.SendAsync(new ImportInvoice(externalRef),
    new DeliveryOptions { Id = DeterministicGuid(externalRef) });
```

If your downstream is idempotent on a business key (e.g. external invoice
reference), generate the envelope id from that key to make Wolverine collapse
duplicates without the handler having to know.

See `tutorials/idempotency.md` upstream for a full walkthrough.

## Dead letter storage

A message that exhausts its retry / requeue policies is moved to dead letter
storage by default. View, retry, or discard via CLI:

```bash
dotnet run -- storage status              # counts in inbox/outbox/dead letter
dotnet run -- storage release             # release a held message id back to the inbox
dotnet run -- describe                    # part of the report covers dead-letter wiring
```

Endpoint-specific DLQs (e.g. RabbitMQ x-dead-letter-exchange, ASB DLQ, SQS DLQ
configured at queue creation time) are configured on the transport — see
[transports.md](transports.md). Wolverine also supports a generic
"database-backed" dead letter store via the same message store you picked.

## Claim checks

Large message? Store the payload externally (Azure Blob, S3, file system) and
let Wolverine pass a claim check id:

```csharp
opts.UseClaimChecks<AzureBlobClaimCheckStore>(threshold: 256.Kilobytes());
```

The receiver fetches the payload transparently from the same store.

## Stale message recovery

Defense-in-depth for inbox/outbox stalls:

```csharp
opts.Durability.OutboxStaleTime = 1.Hours();
opts.Durability.InboxStaleTime  = 10.Minutes();
```

Older envelopes still owned by a node get "released" so any node can pick them
up. **Don't set `InboxStaleTime` shorter than your worst-case handler runtime
including retries** — you'll trigger spurious re-processing.

## Message identity (for modular monoliths)

Default inbox identity = envelope id. If the **same** envelope is delivered to
multiple modules of one process (e.g. a fanned-out broker subscription with
multiple sticky handlers), Wolverine deduplicates and only one module sees it.

Switch:

```csharp
opts.Durability.MessageIdentity = MessageIdentity.IdAndDestination;
```

Each handler subscription has its own identity, so all of them see the message.
Required when running modular-monolith with `MultipleHandlerBehavior.Separated`.

## Operating the durability subsystem

- `dotnet run -- describe` — confirm durable endpoints, inbox/outbox config.
- `dotnet run -- check-env` — connectivity probe.
- `dotnet run -- resources setup` — provision the inbox/outbox schema and any
  transport-defined queues / exchanges.
- Health checks: `services.AddWolverineHealthCheck()` exposes durability +
  listener status.
- Leadership: Wolverine elects a leader node to run scheduled / recovery work.
  See [persistence.md](persistence.md) and `durability/leadership-and-troubleshooting.md`
  upstream.
