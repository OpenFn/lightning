# KAFKA TESTING

A brief, unstructured summary of testing Elixir integration for Kafka.

## The North...Kafka remembers

If you reconnect to a running Kafka container using the same group identifier, 
Kafka will remember the last offset that you acknowledged and only send the
consumer messages after that.

kcat seems to generate a new identifier on each connection.

## Dummy Kafka Consumer

`Lightning.KafkaSubscriber` is a dummy subscriber that just writes whatever is
received to the log (as an error, to make it easier to spot).

## Additional test tooling

The following tools are useful if you want non-Elixir tooling that can be used
to validate behaviour:

- `kafka-console-producer.sh` - can be run from within the Kafka container to
  produce a message.
- `kafka-console-consumer.sh` - can be run from within the Kafka container to
  consume a message
- `kcat` - a CLI tool that is useful to tst connections originating from
  outside the container

The Kafka container has a number of CLI
[tools](https://docs.confluent.io/kafka/operations-tools/kafka-tools.html)
that can be useful for testing.

## Test containers

There are two docker-compose files available for test purposes. 

- `docker-compose.kafka-testing.yml` - this starts up a single Kafka node
  running Zookeeper and uses SASL authentication in addition to a
  non-authenticated broekr.
- `docker-compose-kafka-testing-2.yml` - this starts up a single Kafka node
  running KRaft and does not use authentication.

In the subsections below, I will refer to the above as the Zookeeper and KRaft
instances respectively.

### Zookeeper Container

To start the Zookeeper container, run:

```
docker-compose -f docker-compose.kafka-testing.yml up -d
```

A non-authenticated listener listens on port 9092, while a listener requiring
SASL authentication can be found at port 9094.

To open the interactive (internal) producer, run:

```
docker exec -it lightning_kafka_1 kafka-console-producer.sh --producer.config /opt/bitnami/kafka/config/producer.properties --bootstrap-server kafka:9092 --topic test
```

To run the internal consumer:

```
docker exec -it lightning_kafka_1 kafka-console-consumer.sh --consumer.config /opt/bitnami/kafka/config/consumer.properties --bootstrap-server kafka:9092 --topic test --from-beginning
```

To consume messages using kcat, you can setup `~/.config/kcat.conf`:

```
security.protocol=sasl_plaintext
sasl.mechanism=PLAIN
sasl.username=user
sasl.password=bitnami
```

And then consume messages by running:

```
kcat -b localhost:9094 -t test -C
```

If you wish to not use the config file, or you wish to override authentication parameters:

```
kcat -b localhost:9094 -t test -C -X security.protocol=sasl_plaintext -X sasl.mechanism=PLAIN -X sasl.username=user -X sasl.password=bitnami
```

To test consumption from an IEx session:

```
# Using a client defined in config
group_config = [
  offset_commit_policy: :commit_to_kafka_v2,
  offset_commit_interval_seconds: 5,
  rejoin_delay_seconds: 2,
  reconnect_cool_down_seconds: 10
]

config = %{
  client: :kafka_client,
  group_id: "brod_consumer_group",
  topics: ["test"],
  cb_module: KafkaSubscriber,
  group_config: group_config,
  consumer_config: [begin_offset: :earliest]
}

{:ok, pid} = :brod.start_link_group_subscriber_v2(config)

# Using a client defined in the IEx session
# I found that it was less noisy if I commented out the brod config
# in config/runtime.exs before running the below.

group_config = [
  offset_commit_policy: :commit_to_kafka_v2,
  offset_commit_interval_seconds: 5,
  rejoin_delay_seconds: 2,
  reconnect_cool_down_seconds: 10
]

:brod.start_client(
  [{"localhost", 9094}],
  :dynamic_client,
  [{:sasl, {:plain, "user", "bitnami"}}]
)

config = %{
  client: :dynamic_client,
  group_id: "brod_dynamic_consumer_group",
  topics: ["test"],
  cb_module: KafkaSubscriber,
  group_config: group_config,
  consumer_config: [begin_offset: :earliest]
}

{:ok, pid} = :brod.start_link_group_subscriber_v2(config)
```
```
```

### KRaft container

To start the Kraft container, run:

```
docker-compose -f docker-compose.kafka-testing-2.yml up -d
```

There is only an unauthenticated listener, on port 9092.

To open the interactive (internal) producer, run:

```
docker exec -it lightning_kafka-01_1 kafka-console-producer.sh --producer.config /opt/bitnami/kafka/config/producer.properties --bootstrap-server kafka-01:9092 --topic test
```

To run the internal consumer:

```
docker exec -it lightning_kafka-01_1 kafka-console-consumer.sh --consumer.config /opt/bitnami/kafka/config/consumer.properties --bootstrap-server kafka-01:9092 --topic test --from-beginning
```

If you want to use kcat, you will need to remove any SASL auth settings from
`~/.config/kcat.conf` if it exists and then run:

```
kcat -b localhost:9092 -t test -C
```

To test consumption from an IEx session:

```
# Using a client defined in the IEx session
# I found that it was less noisy if I commented out the brod config
# in config/runtime.exs before running the below.

group_config = [
  offset_commit_policy: :commit_to_kafka_v2,
  offset_commit_interval_seconds: 5,
  rejoin_delay_seconds: 2,
  reconnect_cool_down_seconds: 10
]

:brod.start_client(
  [{"localhost", 9092}],
  :dynamic_client
)

config = %{
  client: :dynamic_client,
  group_id: "brod_dynamic_consumer_group",
  topics: ["test"],
  cb_module: KafkaSubscriber,
  group_config: group_config,
  consumer_config: [begin_offset: :earliest]
}

{:ok, pid} = :brod.start_link_group_subscriber_v2(config)
```

## History

Caveat: This was my first time trying to do anything with Kafka, so if
you think I got something wrong, I probably did.

The aim of the initial exercise was to be able to consume messages from
Kafka in a running container by making authenticated requests from a consumer
written in Elixir.

The current Kafka setup was a minimum-effort exercise to produce a
minimally-viable solution. As such, it will probably make seasoned Kafka
operators cry (`docker-compose.kafka-testing.yml`).

The containers can be started by running
`docker-compose -f docker-compose.kafka-testing.yml up -d`.

I initially started by testing `kafka_ex` against a container that was
running KRaft (which is the replacement to Zookeeper). Initial difficulties
connecting resulted in me changing to a Kafka/Zookeeper combination.

I could consume messages using kafka_ex, but when I tried to connect using
`SASL` this failed. There is currently a GH issue regarding this that has
been around for several years with no resolution in sight.

I then switched to `brod`. With `brod` I could successfully make authenticated
requests to the Kafka container. I could even 'dynamically' create a new client.
