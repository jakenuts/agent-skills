---
name: wolverine
description: >-
  WolverineFx (.NET) framework for in-process command/event handling, asynchronous
  messaging, durable inbox/outbox, sagas, and HTTP endpoints. Use when working in a
  .NET project that references `WolverineFx*` packages, calls `UseWolverine()`, or
  whenever the user asks about Wolverine handlers, message routing, transactional
  outbox, transports (RabbitMQ, Azure Service Bus, SQS, Kafka, NATS, Pulsar,
  PostgreSQL, SQL Server, Redis, MQTT, etc.), Wolverine.HTTP endpoints, Marten/EF
  Core/RavenDb integration, sagas/process managers, middleware, cascading messages,
  side effects, FluentValidation integration, tracked-session testing, or migrating
  to/from MediatR/NServiceBus/MassTransit. Also applies to Critter Stack and JasperFx
  conversations that mention Wolverine.
---

# Wolverine

WolverineFx is a .NET runtime for **command execution and message handling**. One
mental model covers many use cases: a method handles a message; the rest is just
where the message comes from and what happens after it succeeds.

- **In-process mediator** — invoke a command, run a handler. Lower ceremony than MediatR.
- **Local message bus** — fire-and-forget across in-memory queues with optional durability.
- **Distributed messaging** — same handler model, fronted by RabbitMQ, Azure Service Bus, SQS/SNS, Kafka, NATS, Pulsar, MQTT, Redis, GCP Pub/Sub, PostgreSQL, SQL Server, etc.
- **HTTP endpoints** — `WolverineFx.Http` exposes methods as ASP.NET Core endpoints with the same conventions.
- **Durable messaging** — inbox/outbox on top of Marten, EF Core, or RavenDb for transactional consistency.
- **Sagas / process managers** — long-running stateful workflows.

CQRS and event sourcing are **one** thing Wolverine pairs well with (via Marten),
but most features apply equally to plain command/event-driven services,
modular monoliths, vertical-slice web apps, background workers, and ETL pipelines.
Do not assume a Wolverine question implies event sourcing.

## When agent context is tight

If you only need the API shape for a specific topic, read the matching reference
file below and skip the rest. The list below is the index — load only what you
need for the current task.

| Reference | Load when... |
|-----------|-------------|
| [references/handlers.md](references/handlers.md) | Writing or modifying a handler: discovery rules, signatures, cascading messages, side effects, return types, error policies, FluentValidation, `[Entity]` loading. |
| [references/messaging.md](references/messaging.md) | Sending/publishing/scheduling messages, routing rules, listener config, local queues, conventional routing, topics. |
| [references/transports.md](references/transports.md) | Configuring a specific broker (RabbitMQ, Azure Service Bus, SQS, Kafka, NATS, Pulsar, MQTT, Redis, PostgreSQL/SQL Server transport). |
| [references/http.md](references/http.md) | Building or migrating `WolverineFx.Http` endpoints, mediator-style routes, response/request conventions. |
| [references/durability.md](references/durability.md) | Enabling inbox/outbox, idempotency, dead letter storage, claim checks, transactional middleware. |
| [references/persistence.md](references/persistence.md) | Picking/wiring Marten, EF Core, or RavenDb integration; sagas; multi-tenancy; event sourcing aggregate handlers (only when actually using event sourcing). |
| [references/middleware-and-policies.md](references/middleware-and-policies.md) | Writing conventional middleware, policies, attributes; modifying handler chains. |
| [references/testing-and-ops.md](references/testing-and-ops.md) | Tracked-session integration tests, command-line diagnostics, codegen, logging, health checks, AOT/cold-start tuning. |
| [references/patterns.md](references/patterns.md) | Architectural shape: vertical-slice, modular monolith, mediator-only, railway, ping-pong, leader election, MediatR/MVC/MinAPI migration. |

## Core mental model (always-loaded)

A Wolverine application is `WolverineOptions` configured on the .NET Generic Host:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Host.UseWolverine(opts =>
{
    // routing, transports, durability, policies go here
});

var app = builder.Build();
// Opt into JasperFx CLI commands for `dotnet run -- describe|codegen|...`
return await app.RunJasperFxCommands(args);
```

`IMessageBus` is scoped, injected via DI, and is the single entry point at
runtime:

```csharp
await bus.InvokeAsync(new DebitAccount(1111, 250));            // run handler now, await result
var status = await bus.InvokeAsync<AccountStatus>(cmd);        // request/response
await bus.SendAsync(new DebitAccount(1111, 250));              // requires at least one subscriber
await bus.PublishAsync(new AccountOverdrawn(1111));            // fire-and-forget, OK with 0 subscribers
await bus.ScheduleAsync(new ReminderDue(id), 1.Days());        // delayed
```

A handler is any **public** method on a **public** class with a name like
`Handle` / `HandleAsync` / `Consume` / `ConsumeAsync` on a class suffixed
`Handler` or `Consumer` (or marked `[WolverineHandler]` / `IWolverineHandler`).
The first parameter is the message; the rest are method-injected from DI:

```csharp
public static class DebitAccountHandler
{
    public static IssueDebited Handle(DebitAccount cmd, IDocumentSession session)
    {
        // ...mutate state, return event
        return new IssueDebited(cmd.AccountId);
    }
}
```

Return values are not just data — they're **cascading messages**, **side
effects**, or **storage actions** (see [handlers.md](references/handlers.md)).
This is what lets handlers stay pure functions.

## Critical conventions and gotchas

These are the things agents trip over. Read this section before touching
unfamiliar handler code.

- **No runtime reflection in the hot path.** Wolverine generates an adapter class per handler at startup (or ahead of time). `dotnet run -- codegen write` writes the generated code to `Internal/Generated/` so you can read what Wolverine is actually doing — use this when something seems "magic".
- **IoC must be transparent.** Prefer `AddSingleton<T>()` / `AddScoped<TInterface, TImpl>()` / constructor injection. Opaque lambda factories (`AddScoped<T>(sp => ...)`) that handlers consume now throw at startup (Wolverine 6); use `opts.CodeGeneration.AlwaysUseServiceLocationFor<T>()` only as a deliberate escape hatch.
- **Public-everything rule.** Handler types, handler methods, and message types must all be public. So must FluentValidation validators (or set `IncludeInternalTypes`).
- **Don't abstract `IMessageBus`.** Inject it as a method parameter when you need it; otherwise prefer returning cascading messages so handlers stay testable as pure functions.
- **Discovery is allow-list based.** Only the application assembly is scanned by default. Other assemblies need `[assembly: WolverineModule]` or `opts.Discovery.IncludeAssembly(...)`.
- **Generated code is not auto-regenerated.** When you change a handler signature or middleware while using `Static`/`Auto` codegen mode, delete the stale file under `Internal/Generated/` (or run `dotnet run -- codegen write`).
- **`InvokeAsync` only auto-applies Retry policies** from your error rules. Requeue / discard / dead-letter only apply when a message is processed from a listener.
- **Don't read CQRS/event-sourcing language into a Wolverine question.** Wolverine handles plain commands and events just as well; only the Marten integration adds event-sourcing-specific helpers (`[Aggregate]`, `IEvent<T>`, event forwarding). Skip [persistence.md](references/persistence.md)'s event-sourcing section unless the user is actually using `IDocumentSession.Events` or Marten projections.
- **Local queues are real.** A message with a known handler is, by default, routed to a per-message-type in-process queue — not invoked synchronously. Use `InvokeAsync` if you need synchronous semantics; configure `opts.LocalQueue(...)` to tune parallelism and durability.

## Diagnostics first

Before debugging routing, handler discovery, or codegen issues, run:

```bash
dotnet run -- describe        # full configuration dump: handlers, routes, endpoints, options
dotnet run -- codegen preview # see the generated adapter code Wolverine produced
dotnet run -- codegen write   # persist generated code into Internal/Generated/
dotnet run -- check-env       # validate environment & connectivity (transports, message store)
dotnet run -- resources setup # provision broker/db resources Wolverine knows about
```

`opts.DescribeHandlerMatch(typeof(SomeHandler))` prints a textual report
explaining why Wolverine did or did not pick a type up as a handler. Reach
for it when handlers "go missing".

## Picking the right next reference

- "I need to write/edit a handler" → `handlers.md`
- "How do I send/publish/route messages" → `messaging.md`, plus `transports.md` for the specific broker
- "I'm wiring up RabbitMQ / Kafka / SQS / ASB / NATS / ..." → `transports.md`
- "HTTP endpoint with Wolverine" → `http.md`
- "Transactional outbox / dead-letter / idempotency" → `durability.md`, plus `persistence.md` for the store
- "Saga / long-running workflow" → `persistence.md` (sagas section)
- "Custom middleware / cross-cutting policy" → `middleware-and-policies.md`
- "Integration test / cold-start / CLI / logging" → `testing-and-ops.md`
- "Migrate from MediatR/MVC/MinAPI" or "should this be a modular monolith" → `patterns.md`
