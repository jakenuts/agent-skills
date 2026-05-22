# Handlers

Everything about authoring a Wolverine handler: discovery, signatures, return
values, error handling, validation, entity loading.

## Contents

- [Discovery rules](#discovery-rules)
- [Legal signatures](#legal-signatures)
- [Method-injected parameters](#method-injected-parameters)
- [Return values: cascading, side effects, storage, tuples](#return-values)
- [Loading entities with `[Entity]`](#loading-entities-with-entity)
- [Compound handlers (`Before` / `Load` / `Validate` / `After` / `Finally`)](#compound-handlers)
- [Stopping execution from a `Before` method](#stopping-execution)
- [Error handling policies](#error-handling-policies)
- [FluentValidation integration](#fluentvalidation-integration)
- [DataAnnotations / batching / rate limiting / sticky / timeout / multi-tenancy](#smaller-features)
- [Multiple handlers per message type](#multiple-handlers-per-message-type)

## Discovery rules

Wolverine scans the **application assembly** plus any assembly marked
`[assembly: WolverineModule]` or added via
`opts.Discovery.IncludeAssembly(typeof(X).Assembly)`.

A type is a handler if it is public, concrete (non-generic), and either:
- implements `Wolverine.IWolverineHandler`, or
- is decorated `[WolverineHandler]`, or
- has a type name ending in `Handler` or `Consumer`.

A method on a handler type is a handler method if it is public, has the message
as the first parameter, and is named `Handle`/`HandleAsync`/`Consume`/`ConsumeAsync`.
Both instance and `static` methods work; `static` is a touch faster.

When discovery seems wrong, dump it:

```csharp
Console.WriteLine(opts.DescribeHandlerMatch(typeof(MyMissingMessageHandler)));
// or globally
dotnet run -- describe
```

## Legal signatures

```csharp
public class OrderHandler
{
    public void Handle(PlaceOrder cmd) { }                          // sync, no result
    public Task HandleAsync(PlaceOrder cmd, IRepo repo) => ...;     // async, method-injected service
    public OrderPlaced Handle(PlaceOrder cmd) => new(cmd.Id);       // cascades a single message
    public IEnumerable<object> Handle(PlaceOrder cmd)               // cascades many
    {
        yield return new OrderPlaced(cmd.Id);
        yield return new InventoryReserved(cmd.Id);
    }
    public (OrderPlaced, ReserveInventory) Handle(PlaceOrder cmd)   // tuple — same as IEnumerable<object>, more readable
        => (new(cmd.Id), new(cmd.Id));
}
```

Rules:
- First parameter is the message.
- Multiple handler methods for the same type are legal — see [multiple handlers](#multiple-handlers-per-message-type).
- The message type may be an interface or abstract class.
- The handler type may use primary-constructor / constructor injection; the
  instance is created per-message and disposed afterward.

## Method-injected parameters

After the message, you can declare:

- IoC services (any registered type) — preferred over constructor injection.
- `Envelope` — metadata about the current message (headers, attempts, id, etc.).
- `IMessageContext` or `IMessageBus` — scoped to the current message.
- `CancellationToken`.
- `DateTime` / `DateTimeOffset` named `now` — easier to fake in tests.
- `ILogger` — Wolverine wires the right `ILogger<MessageType>` for you.

## Return values

A handler's return type drives behavior. Pick the one that matches intent:

| Return | What Wolverine does |
|--------|---------------------|
| `void` / `Task` / `ValueTask` | Nothing extra. |
| A message type | Publishes the value as a **cascading message** after the handler succeeds. |
| `null` | Ignored (legal). |
| `object` | Same as above — cascades whatever you returned (or nothing if null). |
| `IEnumerable<object>`, `object[]`, `Task<object[]>`, `IAsyncEnumerable<object>` | Each element is a cascading message. |
| C# tuple `(A, B)` | Each tuple item is treated independently per its type. |
| `OutgoingMessages` | A typed collection with helpers: `.RespondToSender(...)`, `.Delay(msg, 5.Minutes())`, `.Schedule(msg, at)`. Best when mixing side effects + messages. |
| Anything implementing `ISideEffect` | Wolverine calls its `Execute` / `ExecuteAsync(...)` method **inline**, in the same transaction (see [side effects](#side-effects)). |
| `IStorageAction<T>` / `Storage.Insert/Update/Delete/Store/Nothing<T>()` | Persistence side effects honored by Marten/EF Core/RavenDb integration. |
| `Envelope` wrapping a message | Lets you customize delivery (delay, schedule, headers). |
| `Respond.ToSender(msg)` | Sends the message back to the original sender, not via routing. |

### Cascading messages

```csharp
public class CascadingHandler
{
    public MyResponse Handle(MyMessage m) => new MyResponse();
}
```

After `Handle` succeeds (and inside the same transaction if transactional
middleware is in play), Wolverine publishes `MyResponse` through normal routing.
Returning `null` skips publication.

Customize per-message delivery via fluent helpers — they wrap the message in an
`Envelope`:

```csharp
public static IEnumerable<object> Consume(Incoming m)
{
    yield return new Message1().DelayedFor(10.Minutes());
    yield return new Message2().ScheduledAt(DateTimeOffset.UtcNow.AddDays(1));
    yield return new Message3()
        .WithDeliveryOptions(new DeliveryOptions().WithHeader("foo", "bar"));
    yield return Respond.ToSender(new Message4());
}
```

`OutgoingMessages` is the most explicit option when mixing types:

```csharp
public static OutgoingMessages Handle(Incoming m)
{
    var messages = new OutgoingMessages { new Message1(), new Message2() };
    messages.RespondToSender(new Message4());
    messages.Delay(new Message5(), 5.Minutes());
    return messages;
}
```

### Side effects

`ISideEffect` makes "do something with the outside world" an explicit return
value so the handler stays a pure function (unit-testable without mocking).

```csharp
public record WriteFile(string Path, string Contents) : ISideEffect
{
    public Task ExecuteAsync(PathSettings settings) // method-injectable from DI
        => File.WriteAllTextAsync(Path, Contents);
}

public class RecordTextHandler
{
    public WriteFile Handle(RecordText cmd) =>
        new(cmd.Id + ".txt", cmd.Text);
}
```

Unlike cascading messages, side effects run **inline** within the same logical
transaction; cascaded messages run later, with their own retry loop.

## Loading entities with `[Entity]`

```csharp
[WolverinePost("/api/todo/update")]   // works for messages too
public static Update<Todo> Handle(
    RenameTodo command,
    [Entity] Todo todo)               // loaded via IDocumentSession / DbContext / IAsyncDocumentSession
{
    todo.Name = command.Name;
    return Storage.Update(todo);
}
```

- Default lookup uses `Id` or `<TypeName>Id` on the message / route arg.
- Override with `[Entity("orderId")]` or `[Entity(ValueSource = ValueSource.RouteValue)]`.
- Required by default: missing entity → 404 (HTTP) or skip-with-log (message handler).
  Use `[Entity(Required = false)]` to allow null, or set
  `opts.EntityDefaults.OnMissing = OnMissing.ProblemDetailsWith404` globally.
- Works with Marten, EF Core, RavenDb. EF Core needs to deduce which
  `DbContext` owns the entity.

For Marten event-sourced aggregates, `[Aggregate]` / `[ReadAggregate]` /
`[WriteAggregate]` are similar but load via `AggregateStreamAsync` — see
[persistence.md](persistence.md).

## Compound handlers

Add helper methods on the handler class for `Load`, `Validate`, `Before`,
`After`, `Finally` lifecycle hooks — no attributes needed:

```csharp
public static class DebitAccountHandler
{
    // runs first; returns an Account that gets injected into Handle
    public static Task<Account?> LoadAsync(DebitAccount cmd, IDocumentSession s, CancellationToken ct)
        => s.LoadAsync<Account>(cmd.AccountId, ct);

    // also runs before Handle; can stop processing
    public static HandlerContinuation Validate(DebitAccount cmd, Account? account)
        => account is null ? HandlerContinuation.Stop : HandlerContinuation.Continue;

    public static void Handle(DebitAccount cmd, Account account)
    {
        account.Balance -= cmd.Amount;
    }

    public static void Finally(ILogger log, Envelope env)
        => log.LogInformation("Debit done {Id}", env.Id);
}
```

Method-name buckets (case sensitive):

| Phase | Method names |
|-------|--------------|
| Before the handler | `Before`, `BeforeAsync`, `Load`, `LoadAsync`, `Validate`, `ValidateAsync` |
| After (only on success) | `After`, `AfterAsync`, `PostProcess`, `PostProcessAsync` |
| In `finally` (always) | `Finally`, `FinallyAsync` |

Values returned from `Before`/`Load` are usable as parameters to the handler
and to later phase methods.

## Stopping execution

Any `Before`/`Validate` method may return `HandlerContinuation.Stop` (alone or
as part of a tuple) to short-circuit the handler. Combine with `OutgoingMessages`
to emit a reply at the same time:

```csharp
public static (HandlerContinuation, OutgoingMessages) Validate(MaybeBadThing t)
    => t.Number > 10
        ? (HandlerContinuation.Stop, [new RejectYourThing(t.Number)])
        : (HandlerContinuation.Continue, []);
```

## Error handling policies

Configure globally on `WolverineOptions`:

```csharp
opts.OnException<TimeoutException>()
    .RetryWithCooldown(50.Milliseconds(), 100.Milliseconds(), 250.Milliseconds())
    .WithFullJitter();                        // or .WithBoundedJitter(0.25) / .WithExponentialJitter()

opts.OnException<SqlException>()
    .ScheduleRetry(1.Seconds(), 5.Seconds(), 30.Seconds());

opts.OnException<InvalidMessageException>().Discard();
opts.OnException<TimeoutException>().MoveToErrorQueue();

opts.OnException<SystemUnavailableException>()
    .Requeue()
    .AndPauseProcessing(10.Minutes());        // pauses just the failing listener
```

Per-message via attribute: `[RetryNow(typeof(SqlException), 50, 100, 250)]`.

Actions: `Retry`, `RetryWithCooldown`, `Requeue`, `ScheduleRetry`,
`ScheduleRetryIndefinitely`, `Discard`, `MoveToErrorQueue`,
`PauseThenRequeue`/`AndPauseProcessing`.

**Gotcha:** Calling `IMessageBus.InvokeAsync()` only honors **Retry** / **RetryWithCooldown**
automatically. The other actions only apply to messages received from a listener.

Add jitter (one strategy per rule) to avoid thundering herds:
`WithFullJitter()` (×1–×2), `WithBoundedJitter(0.25)` (+0%–+25%),
`WithExponentialJitter()` (spread grows per attempt).

## FluentValidation integration

```csharp
opts.UseFluentValidation();    // discovers AbstractValidator<T> from scanned assemblies
// or
opts.UseFluentValidation(RegistrationBehavior.ExplicitRegistration);
```

- Validators must be public (or set `IncludeInternalTypes` and register as
  Singletons).
- The middleware throws `ValidationException` on failure and Wolverine's policy
  discards the message. For HTTP, use the dedicated `WolverineFx.Http`
  middleware that returns `ProblemDetails` — see [http.md](http.md).
- Skip for handlers whose message has no registered validator (auto-skipped).
- If validators need scoped IoC services that force service-location codegen,
  write a `Validate`/`ValidateAsync` compound-handler method instead.

## Smaller features

- **DataAnnotations**: `opts.UseDataAnnotations();` — same idea, simpler subset.
- **Batching**: For high-volume work, define a batch handler that consumes
  `IReadOnlyList<TMessage>` and configure with `opts.BatchMessagesOf<T>(batchSize, window)`.
- **Rate limiting**: `opts.Policies.AddMiddleware(...)` or per-handler attributes;
  Wolverine ships a token-bucket-style limiter — read the source if you need the API.
- **Sticky handlers** (`[StickyHandler("queue-name")]`): in `Modular Monolith`/event-driven
  setups, pin one of several handlers for a type to a specific listener; or set
  `opts.MultipleHandlerBehavior = MultipleHandlerBehavior.Separated` globally so
  every handler for a shared type becomes an independent subscription.
- **Timeout**: `[MessageTimeout(seconds)]` on the message type, or `opts.DefaultExecutionTimeout = ...`.
- **Multi-tenancy**: see [persistence.md](persistence.md) — Wolverine threads `TenantId`
  through the envelope and into the matching session.

## Multiple handlers per message type

Default behavior (`ClassicCombineIntoOneLogicalHandler`) merges all handlers
for a single message type into one logical handler that runs in one
transaction. This is rarely what you want in modular monoliths or
event-driven systems.

Switch globally:

```csharp
opts.MultipleHandlerBehavior = MultipleHandlerBehavior.Separated;
```

Now each handler type becomes its own listener/local queue keyed by handler
type name, not message type name. For conventional broker routing this yields
e.g. `MyApp.Module1.OrderCreatedHandler` and `MyApp.Module2.OrderCreatedHandler`
queues, each binding to one handler.
