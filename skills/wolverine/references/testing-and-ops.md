# Testing and Operations

Integration testing, CLI diagnostics, code generation, logging, health
checks, AOT / cold start.

## Contents

- [Unit testing handlers](#unit-testing-handlers)
- [Integration testing with tracked sessions](#integration-testing-with-tracked-sessions)
- [Testing HTTP endpoints with Alba](#testing-http-endpoints-with-alba)
- [Code generation modes](#code-generation-modes)
- [CLI commands](#cli-commands)
- [Logging and observability](#logging-and-observability)
- [Health checks](#health-checks)
- [AOT / cold start](#aot--cold-start)
- [Common diagnostics recipes](#common-diagnostics-recipes)

## Unit testing handlers

Wolverine's whole design pressure is toward pure-function handlers, so unit
tests rarely need a host:

```csharp
[Fact]
public void debit_returns_overdrawn_when_below_zero()
{
    var account = new Account { Id = 1, Balance = 10 };
    var (events, _) = DebitAccountHandler.Handle(new DebitAccount(1, 50), account);
    events.OfType<AccountOverdrawn>().ShouldHaveSingleItem();
}
```

If a handler depends on `IDocumentSession`/`DbContext`, prefer compound
handlers — extract the pure decision into a `Handle(...)` that takes the
already-loaded entity, and put the I/O in a `LoadAsync` method (see
[handlers.md](handlers.md#compound-handlers)).

## Integration testing with tracked sessions

Tracked sessions know when **all** in-flight work is done — including cascaded
messages handled in other local queues — so you can assert without polling.

```csharp
using var host = await Host.CreateDefaultBuilder()
    .UseWolverine(opts =>
    {
        opts.Services.AddSingleton<IAccountRepo, InMemoryAccountRepo>();
    })
    .StartAsync();

var session = await host.InvokeMessageAndWaitAsync(new DebitAccount(111, 300));

session.Sent.SingleMessage<AccountOverdrawn>()
       .AccountId.ShouldBe(111);
```

Advanced shape:

```csharp
var session = await host.TrackActivity()
    .Timeout(1.Minutes())
    .IncludeExternalTransports()                // wait for broker round-trips
    .AlsoTrack(otherHost)                       // span across IHosts (multi-service tests)
    .DoNotAssertOnExceptionsDetected()          // when testing failure paths
    .IgnoreFailureAcks()
    .WaitForMessageToBeReceivedAt<DownstreamCmd>(otherHost)
    .IgnoreMessageType<IAgentCommand>()
    .InvokeMessageAndWaitAsync(new DebitAccount(111, 300));
```

`TrackedSession` exposes collections keyed off `MessageEventType` — `Sent`,
`Received`, `ExecutionStarted`, `ExecutionFinished`, `MessageSucceeded`,
`MessageFailed`, `NoHandlers`, `NoRoutes`, `MovedToErrorQueue`, `Requeued`,
`Scheduled`, `Discarded`. Filter via `.SingleMessage<T>()`, `.MessagesOf<T>()`.

For non-message triggers (file watcher, HTTP endpoint, hosted service),
use `ExecuteAndWaitAsync(action)`:

```csharp
var session = await host.TrackActivity()
    .ExecuteAndWaitAsync(_ => File.WriteAllText(path, "hi"));
session.Sent.SingleMessage<FileAdded>();
```

**Cost note:** `IHost` is expensive — share across tests via a fixture/IClassFixture
or xUnit collection. Tracked sessions themselves are cheap.

The tracked-session extensions live on `IServiceProvider` too (3.13+), so you
can use them when you bootstrap with just a service collection.

## Testing HTTP endpoints with Alba

```csharp
await using var host = await AlbaHost.For<Program>();
var result = await host.Scenario(s =>
{
    s.Post.Json(new CreateTodo("milk")).ToUrl("/api/todos");
    s.StatusCodeShouldBe(201);
});
var dto = result.ReadAsJson<TodoDto>();
```

Combine with `host.TrackActivity().ExecuteAndWaitAsync(_ => host.Scenario(...))`
when an endpoint emits cascaded messages you want to await before asserting.

## Code generation modes

```csharp
opts.CodeGeneration.TypeLoadMode = TypeLoadMode.Dynamic;  // default: build at first use
opts.CodeGeneration.TypeLoadMode = TypeLoadMode.Auto;     // try preloaded, fall back to dynamic, write missing to disk
opts.CodeGeneration.TypeLoadMode = TypeLoadMode.Static;   // only use preloaded types, never compile at runtime
```

| Mode | When |
|---|---|
| Dynamic | Active development; signatures changing. |
| Auto | Local dev with stable signatures; quicker integration tests. |
| Static | Production, AOT, serverless, cold-start-sensitive workloads. |

Workflow for Static:

```bash
# from your service project directory
dotnet run -- codegen write
git add Internal/Generated/
```

If you use `Auto` + `dotnet watch`, exclude the generated folder:

```xml
<ItemGroup>
  <Compile Update="Internal\Generated\**\*.cs" Watch="false" />
</ItemGroup>
```

After changing handler signatures or middleware while in `Static`/`Auto`,
delete the stale generated file — Wolverine does **not** detect drift on its
own.

## CLI commands

`return await app.RunJasperFxCommands(args);` in `Program.cs` unlocks:

```bash
dotnet run -- describe              # config dump: handlers, routes, endpoints, middleware
dotnet run -- check-env             # validates env vars, connection strings, etc.
dotnet run -- resources setup       # provision queues/exchanges/inbox-outbox schema
dotnet run -- resources teardown    # remove provisioned resources
dotnet run -- resources statistics  # counts
dotnet run -- codegen preview       # dump generated source to console
dotnet run -- codegen write         # persist to Internal/Generated/
dotnet run -- codegen test          # compile-check pre-generated code
dotnet run -- storage status        # inbox/outbox/dead-letter counts
dotnet run -- storage release       # release a held envelope
dotnet run -- agents                # list Wolverine background agents
```

`describe` is your first stop for "why isn't this routed/handled/listened?"
questions.

## Logging and observability

- Standard `ILogger<T>` is used throughout — captured by your usual logging
  pipeline (Serilog, OpenTelemetry, etc.).
- Wolverine emits structured logs per message: id, type, attempt, success/failure,
  duration.
- Built-in `Activity` / OpenTelemetry tracing — set
  `opts.Policies.LogMessageStarting(LogLevel.Debug);` to toggle granularity.
- Metrics: `dotnet-counters monitor Wolverine` exposes envelopes-processed,
  dead-lettered, etc. — see `guide/logging.md` upstream for full metric names.
- `[AuditMembers("OrderId","CustomerId")]` on a message type adds those fields
  to log scope automatically.

## Health checks

```csharp
builder.Services.AddWolverineHealthCheck();
app.MapHealthChecks("/health");
```

Covers durability storage connectivity, listener health, and node leadership.

## AOT / cold start

- Use `TypeLoadMode.Static` and check `Internal/Generated/` into source.
- See upstream `guide/aot.md` for Native AOT specifics (annotations,
  trimming-friendly patterns, what's currently unsupported).
- For serverless, also raise `opts.Policies.OnInvocationTimeout(...)` and
  consider `opts.Durability.NodeReassignmentPollingTime = ...` to fit a short
  function lifetime.

## Common diagnostics recipes

**Handler not firing.**
1. `dotnet run -- describe` — is the message type listed?
2. `Console.WriteLine(opts.DescribeHandlerMatch(typeof(MyHandler)));` — explains rejection.
3. Confirm assembly is scanned (`[assembly: WolverineModule]` or `Discovery.IncludeAssembly(...)`).

**Codegen exception at startup.**
- Run `dotnet run -- codegen preview` and read the failing class.
- Usually an opaque DI registration — convert lambda to typed registration, or
  call `opts.CodeGeneration.AlwaysUseServiceLocationFor<T>()`.

**Messages stuck in outbox.**
- `dotnet run -- storage status` to count.
- Check leadership: only one node runs durability recovery; if all nodes lost
  leadership, set `opts.Durability.HealthCheckPollingTime` lower or restart.
- Set `opts.Durability.OutboxStaleTime = ...` so stalled envelopes auto-release.

**HTTP endpoint returns 500 with codegen text.**
- First request raced codegen for the route. Either enable
  `WarmUpRoutes = RouteWarmup.Eager` or pre-generate.
