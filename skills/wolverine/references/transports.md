# Transports

How to wire Wolverine to each supported broker / message store. Pick the
section for the broker you're using.

## Contents

- [Picking a transport](#picking-a-transport)
- [Common patterns across transports](#common-patterns)
- [RabbitMQ](#rabbitmq)
- [Azure Service Bus](#azure-service-bus)
- [Amazon SQS / SNS](#amazon-sqs--sns)
- [Kafka](#kafka)
- [NATS](#nats)
- [Pulsar](#pulsar)
- [MQTT](#mqtt)
- [GCP Pub/Sub](#gcp-pubsub)
- [Redis (Streams)](#redis-streams)
- [Database transports (Postgres / SQL Server / SQLite / MySQL)](#database-transports)
- [TCP / Local](#tcp--local)

## Picking a transport

| If you need... | Pick |
|---|---|
| Fast in-process queues only | Local (built-in) |
| Cross-process testing / lightweight | TCP |
| AMQP, mature pub/sub, fanout | RabbitMQ |
| Azure-native + sessions/topics + dead-lettering | Azure Service Bus |
| AWS-native, high scale | SQS (+ SNS for fanout) |
| High-throughput event streaming, replay | Kafka or Pulsar |
| Lightweight subject-based pub/sub | NATS |
| IoT / device messaging | MQTT |
| GCP-native | GCP Pub/Sub |
| Already using Postgres or SQL Server and want zero ops | Database transports |

Each transport ships as `WolverineFx.<Name>` Nuget. Add the package + a
`opts.Use<Transport>(...)` call.

## Common patterns

All transports share these idioms:

```csharp
opts.Use<Transport>(...)
    .AutoProvision()                   // declare queues/topics at startup
    .AutoPurgeOnStartup()              // wipe at startup (testing only)
    .UseConventionalRouting();         // map message types to endpoints by convention

opts.ListenTo<Transport>("queue-name")
    .UseDurableInbox()                 // inbox-persist incoming envelopes
    .Sequential()                      // one-at-a-time per partition
    .MaximumParallelMessages(20)
    .CircuitBreaker(cb => cb.FailurePercentageThreshold = 25);

opts.PublishMessage<MyMsg>().To<Transport>(...).UseDurableOutbox();

opts.Policies.UseDurableInboxOnAllListeners();   // global durability
opts.Policies.UseDurableOutboxOnAllSendingEndpoints();
```

Set `opts.ServiceName = "orders"` — it appears in OpenTelemetry tags, log
scopes, and is used to namespace conventional routing.

## RabbitMQ

```bash
dotnet add package WolverineFx.RabbitMQ
```

```csharp
opts.UseRabbitMq(new Uri(cfg["rabbit"]!))
    .AutoProvision()
    .DeclareExchange("events", ex => ex.ExchangeType = ExchangeType.Topic)
    .BindExchange("events").ToQueue("orders", "orders.#");

opts.ListenToRabbitQueue("orders")
    .UseDurableInbox()
    .PreFetchCount(50);

opts.PublishMessage<OrderPlaced>().ToRabbitTopic("orders.placed", "events");
opts.PublishAllMessages().ToRabbitExchange("fanout");

// Conventional routing — queue per message type:
opts.UseRabbitMq().UseConventionalRouting();

// Cluster:
opts.UseRabbitMq(rabbit =>
{
    rabbit.HostName = "host1";
    rabbit.AddClusterNode(h => h.HostName = "host2");
});

// Performance: split listener / sender connections
opts.UseRabbitMq(...).UseListenerConnectionOnly();
opts.UseRabbitMq(...).UseSenderConnectionOnly();
```

Notes:
- Connections: by default one listener + one sender, shared across endpoints.
- Multi-broker (3.0+): `opts.AddNamedRabbitMqConnection("alt", uri)` then
  `opts.ListenToRabbitQueue("q").OnConnection("alt")`.
- Dead lettering: `opts.UseRabbitMq().UseDeadLetterQueueing();` (default
  Wolverine DLQ) or `.DisableDeadLetterQueueing()` to opt out.

## Azure Service Bus

```bash
dotnet add package WolverineFx.AzureServiceBus
```

```csharp
opts.UseAzureServiceBus(cfg["ServiceBus"]!)
    .AutoProvision();

opts.ListenToAzureServiceBusQueue("incoming")
    .UseDurableInbox();

opts.PublishMessage<OrderPlaced>().ToAzureServiceBusTopic("orders");
opts.ListenToAzureServiceBusSubscription("orders-mod1", "orders");

// Native scheduled delivery is used automatically.
// Session-based ordering:
opts.ListenToAzureServiceBusQueue("orders")
    .RequireSessions();
```

ASB integration supports the local **emulator** for tests — just point the
connection string at the emulator endpoint.

## Amazon SQS / SNS

```bash
dotnet add package WolverineFx.AmazonSqs
dotnet add package WolverineFx.AmazonSns   # only for SNS publishing
```

```csharp
opts.UseAmazonSqs()
    .Credentials(new BasicAWSCredentials(id, secret))   // or default chain
    .AutoProvision();

opts.ListenToSqsQueue("orders").MaximumParallelMessages(10);

// FIFO with deduplication / message groups:
opts.ListenToSqsQueue("orders.fifo")
    .ConfigureQueueCreation(q => q.FifoQueue = true);

opts.PublishMessage<OrderPlaced>().ToSqsQueue("downstream");
opts.PublishMessage<OrderEvent>().ToSnsTopic("orders-events");

opts.UseAmazonSqs().UseConventionalRouting();  // queue per message type
```

SQS uses its native visibility timeout for retries. Dead-letter queue is
configured per-queue at creation time.

## Kafka

```bash
dotnet add package WolverineFx.Kafka
```

```csharp
opts.UseKafka(bootstrapServers: cfg["kafka"]!);

opts.ListenToKafkaTopic("orders")
    .ConfigureConsumer(c => c.GroupId = "orders-svc");

opts.PublishMessage<OrderPlaced>().ToKafkaTopic("orders");
```

Kafka is push-based but Wolverine still backs envelopes with its inbox when
`UseDurableInbox()` is enabled, giving you exactly-once-ish semantics under
re-balances. Use partitioning if order per key matters:

```csharp
opts.PublishMessage<OrderEvent>()
    .ToKafkaTopic("orders")
    .PartitionByKey<OrderEvent>(e => e.OrderId);
```

## NATS

```bash
dotnet add package WolverineFx.Nats
```

```csharp
opts.UseNats("nats://localhost:4222");
opts.ListenToNatsSubject("orders.>");
opts.PublishMessage<OrderPlaced>().ToNatsSubject("orders.placed");
// JetStream durable consumers also supported via .UseJetStream(...)
```

## Pulsar

```bash
dotnet add package WolverineFx.Pulsar
```

```csharp
opts.UsePulsar(b => b.ServiceUrl(new Uri("pulsar://localhost:6650")));
opts.ListenToPulsarTopic("persistent://public/default/orders");
opts.PublishMessage<OrderPlaced>().ToPulsarTopic("persistent://public/default/orders");
```

## MQTT

```bash
dotnet add package WolverineFx.MQTT
```

```csharp
opts.UseMqtt(c => { c.WithTcpServer("broker", 1883); });
opts.ListenToMqttTopic("devices/+/telemetry");
opts.PublishMessage<DeviceCommand>().ToMqttTopic("devices/{deviceId}/cmd");
```

## GCP Pub/Sub

```bash
dotnet add package WolverineFx.GooglePubsub
```

```csharp
opts.UseGooglePubsub("my-gcp-project").AutoProvision();
opts.ListenToPubsubSubscription("orders-subscription");
opts.PublishMessage<OrderPlaced>().ToPubsubTopic("orders");
```

## Redis (Streams)

```bash
dotnet add package WolverineFx.Redis
```

```csharp
opts.UseRedis("localhost:6379");
opts.ListenToRedisStream("orders").GroupName("orders-svc");
opts.PublishMessage<OrderPlaced>().ToRedisStream("orders");
```

## Database transports

These use SQL tables as queues — handy when you already have the database and
want zero new infrastructure.

### PostgreSQL

```bash
dotnet add package WolverineFx.Postgresql
```

```csharp
opts.UsePostgresqlPersistenceAndTransport(cfg["pg"]!, schemaName: "wolverine");
opts.ListenToPostgresqlQueue("orders").UseDurableInbox();
opts.PublishMessage<OrderPlaced>().ToPostgresqlQueue("orders");
```

### SQL Server

```bash
dotnet add package WolverineFx.SqlServer
```

```csharp
opts.UseSqlServerPersistenceAndTransport(cfg["sql"]!, schemaName: "wolverine");
opts.ListenToSqlServerQueue("orders");
opts.PublishMessage<OrderPlaced>().ToSqlServerQueue("orders");
```

SQLite (testing) and MySQL packages exist with the same shape. They also
double as the **message store** for durability — see [durability.md](durability.md).

## TCP / Local

Built into core Wolverine — no extra package. Useful in tests:

```csharp
opts.ListenAtPort(5555);
opts.PublishAllMessages().ToPort(5556);
```

`Local` (in-memory) is the implicit transport for local queues; nothing extra
to install.
