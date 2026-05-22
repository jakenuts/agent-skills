# Persistence Integration: Marten, EF Core, RavenDb

Wolverine plugs into your persistence layer for the inbox/outbox, sagas,
transactional middleware, and optional event-sourcing helpers (Marten only).
Pick the integration that matches the ORM/store you're already using.

## Contents

- [Decision matrix](#decision-matrix)
- [Marten integration](#marten-integration)
- [EF Core integration](#ef-core-integration)
- [RavenDb integration](#ravendb-integration)
- [Sagas](#sagas)
- [Multi-tenancy](#multi-tenancy)
- [Marten event sourcing helpers (skip unless using ES)](#marten-event-sourcing-helpers)

## Decision matrix

| You have / want | Use |
|---|---|
| Postgres + document/event store, low ceremony | Marten |
| Existing EF Core `DbContext`(s) on Postgres or SQL Server | EF Core |
| RavenDb document store | RavenDb |
| Postgres but no ORM | Marten (it's tiny if you only use it for inbox/outbox) |
| Multiple `DbContext` types | EF Core (Wolverine picks the right one per saga / entity) |
| Event sourcing | Marten |

You can mix: Marten for event-sourced aggregates, EF Core for relational
reporting tables. Just install both NuGets and configure both. The inbox/outbox
itself lives in one of the two databases.

## Marten integration

```bash
dotnet add package WolverineFx.Marten
```

```csharp
builder.Services.AddMarten(opts =>
{
    opts.Connection(cfg.GetConnectionString("marten")!);
    opts.DatabaseSchemaName = "app";

    // (Optional) event sourcing
    opts.Projections.Snapshot<Order>(SnapshotLifecycle.Inline);
})
.IntegrateWithWolverine();   // sets up inbox/outbox + transactional middleware

builder.Host.UseWolverine();
```

What `IntegrateWithWolverine()` does:
- Registers the Wolverine message store in the Marten schema.
- Hooks Marten's `IDocumentSession` lifecycle into the transactional middleware.
- Enables `Storage.Insert/Update/Store/Delete<T>()` side effects to operate on the session.
- Wires the `[Aggregate]` family of attributes for event sourcing.

Then handlers that take `IDocumentSession` get a session that **shares its
transaction with the outbox**:

```csharp
public static OrderCreated Handle(CreateOrder cmd, IDocumentSession s)
{
    var order = new Order(cmd.Id, cmd.Description);
    s.Store(order);
    return new OrderCreated(order.Id);   // staged in outbox; sent on session commit
}
```

Marten-specific outbox API (when you need explicit control outside a handler):
`IMartenOutbox.SendAsync/PublishAsync(msg)` followed by `session.SaveChangesAsync()`.

## EF Core integration

```bash
dotnet add package WolverineFx.EntityFrameworkCore
```

```csharp
var cs = cfg.GetConnectionString("sqlserver")!;

builder.UseWolverine(opts =>
{
    opts.PersistMessagesWithSqlServer(cs);          // or PersistMessagesWithPostgresql

    // Idiomatic: register DbContext + integration in one call
    opts.Services.AddDbContextWithWolverineIntegration<AppDbContext>(
        x => x.UseSqlServer(cs));
    // ...or manually:
    // opts.UseEntityFrameworkCoreTransactions();
});
```

Key points:
- Set `DbContextOptions` lifetime to `Singleton` — Wolverine optimizes around
  this. `AddDbContextWithWolverineIntegration` does it for you.
- The inbox/outbox lives in **one** database. You can have multiple
  `DbContext` types, but they all route inbox/outbox writes through the one
  store you registered.
- For per-test schema resets, see Wolverine's Weasel-managed migrations
  (`UseEntityFrameworkCoreWolverineManagedMigrations()`) — useful in test
  containers.

Handler with `[Transactional]` (or `opts.Policies.AutoApplyTransactions()`):

```csharp
public static OrderCreated Handle(CreateOrder cmd, AppDbContext db)
{
    var order = new Order { Description = cmd.Description };
    db.Orders.Add(order);
    return new OrderCreated(order.Id);   // staged; SaveChanges + outbox flush done by middleware
}
```

## RavenDb integration

```bash
dotnet add package WolverineFx.RavenDb
```

```csharp
builder.Services.AddRavenDb(...);
builder.UseWolverine(opts => opts.UseRavenDbPersistence());
```

API surface mirrors Marten: `IAsyncDocumentSession` is shared with the
transactional middleware; `Storage` side effects, `[Entity]` loading, and
sagas all work.

## Sagas

A saga is a stateful, multi-step process. Inherit `Wolverine.Saga`; the type
becomes both the state document **and** the handler class:

```csharp
public record StartOrder(string OrderId);
public record CompleteOrder(string Id);
public record OrderTimeout(string Id) : TimeoutMessage(1.Minutes());

public class Order : Saga
{
    public string Id { get; set; } = default!;

    public static (Order, OrderTimeout) Start(StartOrder cmd)
        => (new Order { Id = cmd.OrderId }, new OrderTimeout(cmd.OrderId));

    public void Handle(CompleteOrder _) => MarkCompleted();

    public void Handle(OrderTimeout _) => MarkCompleted();

    public static void NotFound(CompleteOrder cmd, ILogger log)
        => log.LogInformation("No order {Id}", cmd.Id);
}
```

- The saga state is persisted to whichever store you wired (Marten by default).
- Wolverine looks for a matching saga by `Id`; if none and the message can
  start a saga, the `Start` method runs.
- `MarkCompleted()` deletes the saga document after the handler commits.
- `TimeoutMessage` subclasses schedule themselves at the TTL; great for
  saga timeouts.
- Static `NotFound(...)` runs when the message has no matching saga state.

Multiple handlers per saga message type require Wolverine 5.10+ with
`MultipleHandlerBehavior.Separated`.

## Multi-tenancy

Wolverine threads `TenantId` through the envelope. Inject one of:

- `IMessageBus.TenantId` to read it inside a handler.
- A tenant-scoped `IDocumentSession` (Marten Conjoined/Database tenancy) or
  `DbContext` (EF Core per-tenant database).

Set the tenant when invoking:

```csharp
await bus.InvokeForTenantAsync("acme", new CreateOrder(...));
await bus.SendAsync(new CreateOrder(...), new DeliveryOptions { TenantId = "acme" });
```

In HTTP, expose a tenant policy or middleware that reads a header/claim and
calls `bus.WithTenant(tenantId).SendAsync(...)`.

Per-store details: see Marten's `multi-tenancy.md`, EF Core's
`durability/efcore/multi-tenancy.md`, and the tutorial
`tutorials/multi-tenancy.md` in the upstream docs.

## Marten event sourcing helpers

**Skip this section unless the project actually uses `IDocumentSession.Events`
for event sourcing.** Wolverine does not require event sourcing; this is purely
sugar for projects already on Marten ES.

### Aggregate handler workflow

```csharp
public static class OrderHandler
{
    // Re-hydrate the Order aggregate from its event stream before the handler runs
    [AggregateHandler]
    public static OrderShipped Ship(ShipOrder cmd, Order order)
    {
        if (order.Status != OrderStatus.Confirmed)
            throw new InvalidStateException();
        return new OrderShipped(order.Id, DateTimeOffset.UtcNow);
    }
}
```

- `[Aggregate]` / `[WriteAggregate]` / `[ReadAggregate]` load the aggregate via
  `AggregateStreamAsync`. Returned events are appended atomically.
- Use `[ReadAggregate]` when the handler only reads — Wolverine skips the
  optimistic version check.
- For pure CQRS + ES projects, return either events or a tuple of
  `(IStorageAction<T>, events...)` — both are committed in one session.

### Event forwarding

```csharp
opts.PublishEventsFromMarten(s => s.MessageOfType<IIntegrationEvent>());
```

Forwards Marten events (or `IEvent<T>` wrappers) to Wolverine routing so
projection updates / integration events fan out without manual code.

### Subscriptions and projections

See upstream `durability/marten/subscriptions.md` and
`durability/marten/event-sourcing.md`. The agent should only load these when
actually working in a Marten ES codebase.
