# Patterns and Migration Guides

Architectural shapes that work well with Wolverine, and how to move existing
code over to it. None of these require event sourcing or full CQRS — they are
general patterns for event-driven and command-driven .NET systems.

## Contents

- [Mediator-only ("just MediatR replacement")](#mediator-only)
- [Vertical slice architecture](#vertical-slice-architecture)
- [Modular monolith](#modular-monolith)
- [Railway-style error handling](#railway-style-error-handling)
- [Process manager / saga](#process-manager--saga)
- [Ping/pong (request-reply across services)](#pingpong-request-reply)
- [Leader election / single-node work](#leader-election--single-node-work)
- [Migrating from MediatR](#migrating-from-mediatr)
- [Migrating from MVC controllers](#migrating-from-mvc-controllers)
- [Migrating from Minimal API](#migrating-from-minimal-api)
- [Migrating from NServiceBus / MassTransit](#migrating-from-nservicebus--masstransit)

## Mediator-only

Use Wolverine as a drop-in mediator in a single process — no broker required.

```csharp
builder.Host.UseWolverine();
app.MapPost("/orders", (CreateOrder cmd, IMessageBus bus) => bus.InvokeAsync(cmd));
```

Compared to MediatR you get: method injection, cascading messages, side
effects, FluentValidation, conventional middleware, durable local queues
(opt-in), and OpenTelemetry — without the per-call container allocations.

See [http.md](http.md) for `MapPostToWolverine<TCmd, TRsp>()` which is even
leaner.

## Vertical slice architecture

Put the message, handler, validator, and (optionally) HTTP endpoint for one
operation into one file or one folder. Wolverine's conventions make this the
path of least resistance:

```
Features/Orders/PlaceOrder/
├── PlaceOrder.cs          // record PlaceOrder(...) + record OrderPlaced(Id)
├── PlaceOrderEndpoint.cs  // [WolverinePost("/orders")] static method
├── PlaceOrderValidator.cs // AbstractValidator<PlaceOrder>
└── PlaceOrderHandler.cs   // static Handle(...) returning (response, event...)
```

No marker interfaces, no `IRequest<TResponse>`, no manual DI registration.
A single PR adds a feature without touching unrelated files.

## Modular monolith

Wolverine 3+ has explicit support for the modular monolith pattern. Key knobs:

- `opts.MultipleHandlerBehavior = MultipleHandlerBehavior.Separated;`
  Multiple modules can each have an `OrderCreatedHandler` for the same event —
  each becomes its own listener with its own local queue.
- `[StickyHandler("queue-name")]` to pin handlers to specific listeners.
- `opts.Durability.MessageIdentity = MessageIdentity.IdAndDestination;` so
  inbox dedup happens per subscription, not per envelope id.
- Use multiple application assemblies with `[assembly: WolverineModule]` so
  each module's handlers are discovered without a central registry.

When the modular monolith later splits into services, the same handlers and
messages move to a separate process and you swap local queues for a broker
(see [transports.md](transports.md)). The handler code itself usually doesn't
change.

## Railway-style error handling

Use return types as the failure channel rather than exceptions, keeping
handlers as pure functions. Cascaded failure messages route exactly like
success messages:

```csharp
public static class PlaceOrderHandler
{
    public static OneOf<OrderPlaced, OrderRejected> Handle(PlaceOrder cmd, IInventory inv)
    {
        if (!inv.HasStock(cmd.Sku)) return new OrderRejected(cmd.Id, "out_of_stock");
        return new OrderPlaced(cmd.Id);
    }
}
```

Wolverine routes each tuple element / `OneOf` branch independently. Pair with
`OutgoingMessages` when you want to emit both a reply to the caller and an
event to a topic.

## Process manager / saga

See [persistence.md](persistence.md) — sagas in Wolverine are a stateful type
that inherits `Wolverine.Saga`. Reach for one when a workflow spans multiple
messages and needs to remember partial state ("3 of 5 confirmations received").

## Ping/pong (request-reply)

```csharp
// Sender:
await bus.SendAsync(new Ping(id), DeliveryOptions.RequireResponse<Pong>());

// Receiver:
public static Pong Handle(Ping ping) => new Pong(ping.Id);
```

The `RequireResponse<Pong>()` header tells the receiver to ship the matching
return type back to the sender's queue instead of through normal routing.
Works across brokers and across processes.

For synchronous request/response in one process, just use
`bus.InvokeAsync<Pong>(new Ping(id))`.

## Leader election / single-node work

Wolverine elects a leader node automatically when you have durability
configured. Use it for scheduled jobs, periodic cleanup, or anything that
must run on exactly one node:

```csharp
public class NightlyReportAgent : IAgent
{
    public Uri Uri => new("agent://nightly-report");
    public Task StartAsync(CancellationToken ct) { ... }
    public Task StopAsync(CancellationToken ct)  { ... }
}

opts.Services.AddSingleton<IAgentFactory, NightlyReportAgentFactory>();
```

The leader hosts the agent; if the leader dies, another node takes over. See
upstream `durability/managing.md` and `tutorials/leader-election.md`.

## Migrating from MediatR

| MediatR | Wolverine |
|---|---|
| `IRequest<T>` / `IRequestHandler<TRequest,TResponse>` | Plain record + plain method named `Handle` |
| `INotification` / `INotificationHandler` | Plain record + return value (cascade) or `IMessageBus.PublishAsync` |
| **Notification dispatch** — sequential, in-process, in-memory | **`PublishAsync`** — routes via per-message-type local queue; parallel by default (use `.Sequential()` to serialize); durable only if outbox is enabled |
| `IPipelineBehavior<T>` | Conventional middleware ([middleware-and-policies.md](middleware-and-policies.md)) |
| `Mediator.Send` | `IMessageBus.InvokeAsync<T>` |
| Constructor-injected services | Method-injected — no constructor required |
| Polymorphic dispatch via `IRequest` | Implicit — match on message type |
| `Stream` requests | Use `IAsyncEnumerable<T>` return from handler |
| Manual validator wiring | `opts.UseFluentValidation()` |

Drop-in steps:

1. Replace `MediatR` package with `WolverineFx` + `UseWolverine()`.
2. Rename `Handle(TRequest, CancellationToken)` to `Handle(TRequest, CancellationToken)` on a class suffixed `Handler` (often already true).
3. Remove `IRequestHandler<,>` interface and base classes — no longer needed.
4. Replace `_mediator.Send(...)` with `_bus.InvokeAsync(...)`.
5. Turn `IPipelineBehavior` into a middleware class with `Before`/`After`/`Finally`.

Upstream `introduction/from-mediatr.md` has a complete migration example.

## Migrating from MVC controllers

Two paths.

**Path A — mediator behind controllers (quickest, smallest blast radius):**

```csharp
[HttpPost("/orders")]
public Task<OrderDto> Post(CreateOrder cmd, [FromServices] IMessageBus bus)
    => bus.InvokeAsync<OrderDto>(cmd);
```

**Path B — replace controllers with Wolverine.HTTP endpoints:**

```csharp
public static class OrderEndpoints
{
    [WolverinePost("/orders")]
    public static (CreationResponse<OrderDto>, OrderPlaced) Create(CreateOrder cmd, ...)
        => ...;
}
```

Path B removes the `Controller` base class, attribute routing duplication, and
`[ApiController]` validation glue — see [http.md](http.md). Path A is
incremental; do it first, then move endpoints over a few at a time.

## Migrating from Minimal API

```csharp
// Before
app.MapPost("/orders", async (CreateOrder cmd, IDocumentSession s, IMessageBus bus) =>
{
    var order = new Order { Description = cmd.Description };
    s.Store(order);
    await bus.PublishAsync(new OrderCreated(order.Id));
    await s.SaveChangesAsync();
    return Results.Created($"/orders/{order.Id}", order);
});

// After
public static class OrderEndpoints
{
    [WolverinePost("/orders")]
    public static (CreationResponse<Order>, OrderCreated) Create(CreateOrder cmd, IDocumentSession s)
    {
        var order = new Order { Description = cmd.Description };
        s.Store(order);
        return (CreationResponse.For(order, $"/orders/{order.Id}"), new OrderCreated(order.Id));
    }
}
```

`SaveChangesAsync` is gone — transactional middleware commits when the endpoint
returns. `OrderCreated` flows through the outbox. OpenAPI metadata is generated
from the type signatures.

## Migrating from NServiceBus / MassTransit

- Replace `IHandleMessages<T>` / `IConsumer<T>` with a class named `*Handler` / `*Consumer` and a `Handle(T)` method. Drop the interface.
- Replace `Bus.Send` / `endpoint.Send` with `IMessageBus.SendAsync`.
- Replace saga base classes with `Wolverine.Saga`.
- Replace per-endpoint pipeline behaviors with conventional middleware.
- Implement `IMessage`/`[WolverineMessage]` on existing message DTOs so they show up in `dotnet run -- describe` (analog to NServiceBus's `IMessage`).
- Configure the same broker via [transports.md](transports.md) — RabbitMQ, ASB, SQS, etc., all supported.
- For interop with the other system during a migration, see upstream
  `tutorials/interop.md` for header/format adapters.
