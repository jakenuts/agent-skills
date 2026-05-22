# Wolverine.HTTP

`WolverineFx.Http` exposes methods as ASP.NET Core endpoints using Wolverine's
codegen pipeline. Lower ceremony than MVC or Minimal API, and reuses the same
middleware and handler conventions as Wolverine messaging.

## Contents

- [Setup](#setup)
- [Endpoint shape](#endpoint-shape)
- [Parameter resolution](#parameter-resolution)
- [Return / response types](#response-types)
- [Validation (FluentValidation)](#validation-fluentvalidation)
- [Loading entities into endpoints (`[Entity]`)](#loading-entities-with-entity)
- [Middleware & policies](#middleware--policies)
- [Mediator-style routes (`MapPostToWolverine`)](#mediator-style-routes)
- [Outbox in HTTP endpoints](#outbox-in-http-endpoints)
- [Integration testing](#integration-testing)
- [Cold start / eager warmup](#cold-start--eager-warmup)

## Setup

```bash
dotnet add package WolverineFx.Http
```

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Host.UseWolverine();
builder.Services.AddWolverineHttp();   // required since 3.0

var app = builder.Build();
app.MapWolverineEndpoints(opts =>
{
    opts.WarmUpRoutes = RouteWarmup.Eager;     // see cold-start section
    opts.UseFluentValidationProblemDetailMiddleware();
});

return await app.RunJasperFxCommands(args);
```

## Endpoint shape

Endpoints are public methods on public classes, decorated with one of:
`[WolverineGet]`, `[WolverinePost]`, `[WolverinePut]`, `[WolverineDelete]`,
`[WolverinePatch]`. Class name does **not** need to end in `Endpoint`, but the
convention helps Wolverine ignore methods that are also message handlers.

```csharp
public static class TodoEndpoints
{
    [WolverineGet("/api/todos/{id}")]
    public static Todo Get([Entity] Todo todo) => todo;

    [WolverinePost("/api/todos")]
    public static (CreationResponse<Todo>, TodoCreated) Create(CreateTodo cmd, IDocumentSession s)
    {
        var todo = new Todo { Name = cmd.Name };
        s.Store(todo);
        return (CreationResponse.For(todo, $"/api/todos/{todo.Id}"), new TodoCreated(todo.Id));
    }
}
```

The same method can act as **both** an HTTP endpoint **and** a message handler
if it follows handler naming conventions and is decorated with a `Wolverine*`
verb attribute — but be aware that route arguments / `HttpContext` are not
available when invoked from the message side, which can cause codegen errors.
Default to suffixing endpoint classes `Endpoint` to avoid the dual role.

## Parameter resolution

Order of precedence:

| Type / decoration | Source |
|---|---|
| `[FromServices]` | IoC |
| `IMessageBus` | New per-request scoped bus |
| `HttpContext` (or members) | Per request |
| Param name matches a route arg | Route value, coerced to the declared type |
| `[FromHeader]` | HTTP header |
| `string`, `int`, `Guid`, `DateTime`, etc. | Query string |
| First "complex" parameter | JSON request body |
| Everything else | IoC |

Force a complex parameter out of the body with `[NotBody]`.

## Response types

| Method returns | Body | Status |
|---|---|---|
| `void` / `Task` / `ValueTask` | empty | 200 |
| `string` (`Task<string>`) | text/plain | 200 |
| `int` (`Task<int>`) | empty | **value** — must be a valid status code |
| `IResult` | varies | varies |
| `CreationResponse` / subclass | JSON | 201 + `Location` header |
| `AcceptResponse` / subclass | JSON | 202 + `Location` header |
| Any other type | JSON | 200 |

For mixed returns, the **first** tuple element is the HTTP response; the rest
are cascading messages or side effects, identical to message handlers:

```csharp
[WolverinePost("/orders")]
public static (CreationResponse<OrderDto>, OrderPlaced, IStorageAction<Order>) Create(...)
{
    // ...
}
```

Wolverine generates the OpenAPI metadata from the type signatures — no
`[ProducesResponseType]` boilerplate required, though you can still use it.

## Validation (FluentValidation)

```bash
dotnet add package WolverineFx.Http.FluentValidation
```

```csharp
app.MapWolverineEndpoints(opts =>
{
    opts.UseFluentValidationProblemDetailMiddleware();
});
```

A validator `AbstractValidator<CreateTodo>` is discovered automatically; on
failure the endpoint returns RFC 7807 `ProblemDetails` with 400 (and 422 when
configured), without invoking the endpoint.

## Loading entities with `[Entity]`

Same as message handlers — see [handlers.md](handlers.md#loading-entities-with-entity):

```csharp
[WolverinePut("/api/todos/{id}/rename")]
public static IStorageAction<Todo> Rename(RenameTodo cmd, [Entity] Todo todo)
{
    todo.Name = cmd.Name;
    return Storage.Update(todo);
}
```

Missing entity → 404 by default. Override with
`[Entity(OnMissing = OnMissing.ProblemDetailsWith404)]` or set
`opts.EntityDefaults.OnMissing = ...` globally.

## Middleware & policies

```csharp
app.MapWolverineEndpoints(opts =>
{
    opts.AddMiddleware(typeof(StopwatchMiddleware));        // global to all wolverine endpoints
    opts.AddPolicy<RequireTenantHeaderPolicy>();
});
```

A `policy` runs at codegen time and can manipulate the endpoint chain — e.g.
require an `Authorize` attribute, inject a tenant lookup `Before` method, etc.
See [middleware-and-policies.md](middleware-and-policies.md).

For per-endpoint middleware, just add a `Before`/`After`/`Finally` method on
the endpoint class — Wolverine inlines it.

## Mediator-style routes

If you've already written message handlers and want a quick HTTP front door:

```csharp
app.MapPostToWolverine<CreateTodo, Todo>("/api/todos");
app.MapGetToWolverine<GetTodo, Todo>("/api/todos/{id}");
```

This still goes through Wolverine but bypasses some allocations the
`IMessageBus.InvokeAsync` path would do. Don't reach for it when you can write
an endpoint method directly — direct endpoints are more flexible.

## Outbox in HTTP endpoints

If the endpoint signature includes a Marten `IDocumentSession` or EF Core
`DbContext`, and you've enabled outbox-aware transactional middleware
(`opts.Policies.AutoApplyTransactions()`), Wolverine commits the DB transaction
**after** the endpoint returns, then publishes any cascaded messages via the
outbox. No `SaveChangesAsync()` call required. See
[durability.md](durability.md).

## Integration testing

```csharp
await using var host = await AlbaHost.For<Program>(x =>
{
    x.ConfigureServices(s => s.AddWolverineHttpTesting());
});

var result = await host.Scenario(s =>
{
    s.Post.Json(new CreateTodo("buy milk")).ToUrl("/api/todos");
    s.StatusCodeShouldBe(201);
});
var dto = result.ReadAsJson<TodoDto>();
```

Combine with [tracked sessions](testing-and-ops.md) when an endpoint cascades
messages and you want to assert on the resulting work.

## Cold start / eager warmup

Wolverine.HTTP generates per-endpoint adapter classes the first time each
route is hit. Two known mitigations:

1. **Pre-generate** at deploy: `dotnet run -- codegen write` and check the
   `Internal/Generated/` files into source. Set
   `opts.CodeGeneration.TypeLoadMode = TypeLoadMode.Static`.
2. **Eager warmup** at startup: `WarmUpRoutes = RouteWarmup.Eager` (above) —
   trades startup time for first-request latency.

If first-request bursts to the same endpoint fail under load (codegen race),
`Eager` warmup avoids it without checking files in.
