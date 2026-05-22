# Messaging: Sending, Routing, Listeners

How to send/publish messages and how Wolverine decides where they go.

## Contents

- [Sending primitives on `IMessageBus`](#sending-primitives)
- [`DeliveryOptions`](#deliveryoptions)
- [Routing rules and precedence](#routing-rules)
- [Explicit subscriptions (`PublishMessage<T>`, `PublishAllMessages`)](#explicit-subscriptions)
- [Local queues](#local-queues)
- [Conventional routing (per-broker)](#conventional-routing)
- [Topics and partitioning](#topics-and-partitioning)
- [Scheduling and expiration](#scheduling-and-expiration)
- [Header propagation](#header-propagation)
- [Diagnosing routes](#diagnosing-routes)

## Sending primitives

```csharp
public static async Task Examples(IMessageBus bus)
{
    await bus.InvokeAsync(new DebitAccount(1, 100));                 // run now, await result
    var status = await bus.InvokeAsync<AccountStatus>(cmd);          // request/response
    await bus.SendAsync(new DebitAccount(1, 100));                   // asserts at least one subscriber
    await bus.PublishAsync(new AccountOverdrawn(1));                 // 0+ subscribers OK
    await bus.ScheduleAsync(new ReminderDue(id), 1.Days());          // delayed
    await bus.ScheduleAsync(new ReminderDue(id), DateTimeOffset.UtcNow.AddHours(1));
}
```

- `InvokeAsync` runs through the handler **inline** in the current thread.
  Only the `Retry` and `RetryWithCooldown` error policies apply automatically.
- `SendAsync` throws `IndicatesNoHandlersException` if no subscriber exists.
  If "a handler isn't firing" after `SendAsync`, this exception is the first
  thing to look for in logs.
- `PublishAsync` is the right choice for events (0+ subscribers OK).
- The `IMessageContext` variant of these (only available **inside a handler**)
  carries the current envelope, so headers like correlation id propagate.

> ⚠️ **Durability warning for MediatR refugees.** `PublishAsync` and
> `SendAsync` are **not** durable by default — they queue in memory and a
> process crash between handler return and broker accept loses the message.
> MediatR's `INotification` was in-process and synchronous, so teams often
> assume "published == persisted." With Wolverine you only get that guarantee
> by enabling the transactional outbox (see [durability.md](durability.md)).
> Equally, MediatR `INotification` handlers run **sequentially in-process**;
> Wolverine routes to per-message-type local queues that may run in **parallel**
> unless you call `.Sequential()` on the queue.

## DeliveryOptions

```csharp
var opts = new DeliveryOptions
{
    DeliverWithin = 5.Seconds(),       // discard if not delivered/processed in time
    DeliverBy = DateTimeOffset.UtcNow.AddHours(1),
    ScheduledTime = DateTimeOffset.UtcNow.AddMinutes(5),
    AckRequested = true,
    ContentType = "application/json",
};
opts.WithHeader("tenant-id", tenant);
opts.RequireResponse<MyResponse>();    // for request/reply
await bus.SendAsync(new MyCmd(), opts);
```

Per-message extension methods (return an `Envelope` you can yield from a handler):

```csharp
new MyMsg().DelayedFor(10.Minutes());
new MyMsg().ScheduledAt(DateTimeOffset.UtcNow.AddDays(2));
new MyMsg().WithDeliveryOptions(new DeliveryOptions().WithHeader("k","v"));
new MyMsg().ToDestination(new Uri("rabbitmq://queue/important"));
new MyMsg().ToEndpoint("important-queue");
```

## Routing rules

When you publish a message, Wolverine resolves a route in this order:

1. **Message forwarding** — if the message type is forwarded (`IForwardsTo<>`), route the destination type instead.
2. **Explicit publishing rules** — if any apply, **only** those are used.
3. **Local routing** — if a handler exists in this process, route to a local queue named after the message type (unless local routing is disabled or made additive).
4. **Conventional broker routing** — RabbitMQ, SQS, ASB, Kafka, etc. conventions if configured.

## Explicit subscriptions

```csharp
opts.PublishMessage<PingMessage>().ToRabbitExchange("pings");
opts.PublishMessage<HeavyJob>().ToLocalQueue("heavy").Durably().Sequential();

opts.PublishAllMessages().ToPort(2222);   // TCP transport, mostly for tests

opts.Publish(rule =>
{
    rule.Message<PingMessage>();
    rule.MessagesImplementing<IIntegrationEvent>();
    rule.MessagesFromNamespaceContaining<OrderPlaced>();
    rule.ToRabbitExchange("events");
});
```

Namespace filters include child namespaces.

## Local queues

In-process queues are the default destination for any message with a known
handler. They're configured like any other endpoint:

```csharp
opts.LocalQueue("important")
    .UseDurableInbox()                       // persisted via inbox
    .Sequential();                           // one at a time

opts.LocalQueue("fanout")
    .MaximumParallelMessages(20)
    .BufferedInMemory();                     // default: in-memory, fast, lossy on crash
```

Convention helpers:

```csharp
opts.Policies.UseDurableLocalQueues();       // all local queues persist
opts.Policies.DisableConventionalLocalRouting(); // force external broker even for local handlers
opts.Policies.ConfigureConventionalLocalRouting().CustomizeQueues((type, queue) =>
{
    if (type.IsInNamespace("MyApp.Background"))
        queue.MaximumParallelMessages(4);
});
```

A message with handler `OrderPlacedHandler` in namespace `MyApp.Orders` lands by
default on local queue `MyApp.Orders.OrderPlaced`.

## Conventional routing

Each broker transport ships a routing convention you opt into. See
[transports.md](transports.md) for the per-broker recipes. Sketch:

```csharp
opts.UseRabbitMq(...)
    .AutoProvision()
    .UseConventionalRouting();               // every message type → queue per type
```

Many conventions support `additive` mode (Wolverine 3.6+) so a message can be
both handled locally **and** published via the broker:

```csharp
opts.Policies.ConfigureConventionalLocalRouting().Additive();
opts.UseRabbitMq(...).UseConventionalRouting();
```

## Topics and partitioning

For pub/sub transports (RabbitMQ topic exchanges, Kafka, MQTT, GCP Pub/Sub, Pulsar),
publish to a topic name or implement `IBroadcaster`:

```csharp
opts.PublishMessage<DomainEvent>().ToRabbitTopic("events", "domain.#");
await bus.BroadcastToTopicAsync("orders.shipped", new OrderShipped(id));
```

Partitioning lets you ensure ordering per key:

```csharp
opts.LocalQueue("orders").Partition(p => p.WithKey<OrderEvent>(e => e.OrderId));
opts.ListenToRabbitQueue("orders").Partition(...);
```

## Scheduling and expiration

- `bus.ScheduleAsync(msg, when)` — needs a message store **or** a transport that
  supports native scheduled delivery (Azure Service Bus, RabbitMQ delayed exchange,
  SQS message timer, etc.).
- `DeliverWithin = TimeSpan` — message is discarded if not delivered/processed
  within the window; cheap defense against backlog blowups.
- Saga timeout: subclass `TimeoutMessage` with a TTL so the saga can self-expire.

## Header propagation

Inside a handler, the `IMessageContext` carries the inbound envelope. Wolverine
automatically copies a configurable header set to outgoing messages. To extend:

```csharp
opts.HeaderPropagation.AlwaysPropagate("x-trace-id", "x-tenant-id");
```

For custom logic, implement `IHeaderPropagator`. Tenant id is propagated
automatically by the multi-tenancy support; see [persistence.md](persistence.md).

## Diagnosing routes

```bash
dotnet run -- describe                # prints all known message types → endpoints
```

Programmatic preview:

```csharp
var runtime = host.Services.GetRequiredService<IWolverineRuntime>();
var router = runtime.RoutingFor(typeof(MyMessage));
foreach (var route in router.Routes) Console.WriteLine(route);
```

`describe` only shows routes for messages Wolverine **knows about**. Mark
external outgoing message types with `IMessage` / `[WolverineMessage]` to make
them discoverable, or `opts.Discovery.IncludeType<MyMessage>()`.
