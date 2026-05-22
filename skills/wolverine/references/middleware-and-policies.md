# Middleware and Policies

How to add cross-cutting behavior. Wolverine middleware is **woven into**
generated handler code at startup — no per-call allocations, no fragile call
stacks.

## Contents

- [Conventional middleware](#conventional-middleware)
- [Lifecycle method names](#lifecycle-method-names)
- [Returning values from `Before` to inject into the handler](#returning-values-from-before)
- [Stopping the chain (`HandlerContinuation.Stop`)](#stopping-the-chain)
- [Sending messages from middleware](#sending-messages-from-middleware)
- [Targeting middleware (by message type, namespace, attribute)](#targeting-middleware)
- [Compound handlers (per-handler middleware)](#compound-handlers)
- [Policies (codegen-time chain modification)](#policies)
- [Attributes that modify chains](#chain-modifying-attributes)
- [How to debug what middleware did](#debugging-middleware)

## Conventional middleware

A middleware class is a plain class (often `static`) with one or more
lifecycle methods. No interfaces, no base classes:

```csharp
public static class StopwatchMiddleware
{
    public static Stopwatch Before()
    {
        var sw = new Stopwatch();
        sw.Start();
        return sw;                                  // becomes available to After/Finally
    }

    public static void Finally(Stopwatch sw, ILogger log, Envelope env)
    {
        sw.Stop();
        log.LogDebug("Envelope {Id} {Type} {Ms}ms",
            env.Id, env.MessageType, sw.ElapsedMilliseconds);
    }
}
```

Register globally:

```csharp
opts.Policies.AddMiddleware<StopwatchMiddleware>();
// or scoped to a subset:
opts.Policies.AddMiddleware<StopwatchMiddleware>(
    chain => chain.MessageType.IsInNamespace("MyApp.Critical"));
```

For HTTP endpoints, add via `MapWolverineEndpoints(o => o.AddMiddleware<T>())`.

## Lifecycle method names

| Phase | Method names |
|---|---|
| Before the handler | `Before`, `BeforeAsync`, `Load`, `LoadAsync`, `Validate`, `ValidateAsync` |
| After the handler (only on success) | `After`, `AfterAsync`, `PostProcess`, `PostProcessAsync` |
| `finally` block (always) | `Finally`, `FinallyAsync` |

Method names are case-sensitive. A class can have any mix of phase methods.

Generated shape:

```csharp
middleware.Before();
try
{
    // handler call
    middleware.After();
}
finally
{
    middleware.Finally();
}
```

## Returning values from `Before`

Anything returned from a `Before`/`Load`/`Validate` method is available as a
parameter (by type) to the handler and to later phase methods:

```csharp
public static class LoadAccount
{
    public static Task<Account?> LoadAsync(IAccountCommand cmd, IDocumentSession s)
        => s.LoadAsync<Account>(cmd.AccountId);
}

public static class DebitHandler
{
    public static void Handle(DebitAccount cmd, Account account)   // injected by middleware
    {
        account.Balance -= cmd.Amount;
    }
}
```

## Stopping the chain

A `Before` method may return `HandlerContinuation.Stop` (alone or in a tuple)
to short-circuit:

```csharp
public static class AccountLookup
{
    public static async Task<(HandlerContinuation, Account?, OutgoingMessages)> LoadAsync(
        IAccountCommand cmd, IDocumentSession s, ILogger log)
    {
        var msgs = new OutgoingMessages();
        var acc  = await s.LoadAsync<Account>(cmd.AccountId);
        if (acc is null)
        {
            log.LogInformation("No account {Id}", cmd.AccountId);
            msgs.RespondToSender(new InvalidAccount(cmd.AccountId));
            return (HandlerContinuation.Stop, null, msgs);
        }
        return (HandlerContinuation.Continue, acc, msgs);
    }
}
```

For HTTP endpoints, prefer returning a `ProblemDetails` from a `Before` method
that returns `IResult` — `HandlerContinuation` is not honored by Wolverine.HTTP.

## Sending messages from middleware

Either inject `IMessageBus`:

```csharp
public static async Task<HandlerContinuation> ValidateAsync(MaybeBad t, IMessageBus bus)
{
    if (t.Number > 10)
    {
        await bus.PublishAsync(new RejectYourThing(t.Number));
        return HandlerContinuation.Stop;
    }
    return HandlerContinuation.Continue;
}
```

…or return `OutgoingMessages`, which avoids coupling to the bus:

```csharp
public static (HandlerContinuation, OutgoingMessages) Validate(MaybeBad t)
    => t.Number > 10
        ? (HandlerContinuation.Stop, [new RejectYourThing(t.Number)])
        : (HandlerContinuation.Continue, []);
```

## Targeting middleware

```csharp
// Only message types in a namespace
opts.Policies.AddMiddleware<AuditMiddleware>(c =>
    c.MessageType.IsInNamespace("MyApp.Money"));

// Only messages implementing an interface (works for `IAccountCommand` etc.)
opts.Policies.ForMessagesOfType<IAccountCommand>().AddMiddleware<AccountLookup>();
```

Conventional matching beats reflection-at-runtime — Wolverine evaluates the
predicate at codegen time, then emits the middleware inline only for matching
chains, so the runtime pays nothing for non-matching messages.

## Compound handlers

Putting middleware methods directly on the handler class is often cleaner than
a separate type — see [handlers.md](handlers.md#compound-handlers). Compound
handlers are first-class; no decoration needed.

## Policies

A policy modifies handler chains at codegen time. Use it when you need to apply
or generate middleware based on something computed from the chain itself
(attributes, return type, interface implementation):

```csharp
public class TenantHeaderPolicy : IChainPolicy
{
    public void Apply(IReadOnlyList<IChain> chains, GenerationRules rules, IServiceContainer container)
    {
        foreach (var chain in chains.Where(c => c.HandlerCalls().Any(call =>
            call.HandlerType.Implements<IRequireTenant>())))
        {
            chain.Middleware.Insert(0, new RequireTenantHeaderFrame());
        }
    }
}

opts.Policies.Add<TenantHeaderPolicy>();
```

For HTTP-specific policies (e.g. always add `Authorize`):

```csharp
app.MapWolverineEndpoints(o => o.AddPolicy<RequireAuthPolicy>());
```

Most teams never need a custom policy — the bundled conventional middleware
and `AddMiddleware<T>(filter)` cover 95% of cases.

## Chain-modifying attributes

Some attributes mutate the chain by themselves:

- `[Transactional]` — wraps the handler in a DB transaction + outbox flush.
- `[StickyHandler("queue")]` — pins this handler to a specific listener.
- `[MessageTimeout(seconds)]` — applies an execution timeout.
- `[RetryNow(typeof(SqlException), 50, 100, 250)]` — per-message error rule.
- `[Aggregate]` / `[ReadAggregate]` / `[WriteAggregate]` — Marten event sourcing.
- `[Entity]` — entity loading (see [handlers.md](handlers.md)).

All of these are implemented as policies under the hood — you can write your
own attribute by deriving from `ModifyChainAttribute`.

## Debugging middleware

```bash
dotnet run -- codegen preview      # print the generated handler/endpoint code
dotnet run -- codegen write        # persist it to Internal/Generated/
dotnet run -- describe             # which middleware is bound where
```

Reading the generated source is the single best way to confirm a middleware is
actually being applied to a given handler chain — Wolverine doesn't hide
anything from you, it's all plain C#.
