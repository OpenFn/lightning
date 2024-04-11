# KAFKA TESTING

A brief, unstructured summary of testing Elixir integration for Kafka.

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
requests to the Kafka container. I could even 'dynamically' create a new client
(see examples below):

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

# Using a client define din the IEx session

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
  group_id: "brod_consumer_group",
  topics: ["test"],
  cb_module: KafkaSubscriber,
  group_config: group_config,
  consumer_config: [begin_offset: :earliest]
}

{:ok, pid} = :brod.start_link_group_subscriber_v2(config)
```

## Useful testing tools

### Kafka CLI tools

The Kafka container has a number of CLI
[tools](https://docs.confluent.io/kafka/operations-tools/kafka-tools.html)
that can be useful for testing.

To produce a message using the internal client:

```
docker exec -it lightning_kafka_1 kafka-console-producer.sh --producer.config /opt/bitnami/kafka/config/producer.properties --bootstrap-server kafka:9092 --topic test
```

To consume a message using the internal client:

```
docker exec -it lightning_kafka_1 kafka-console-consumer.sh --consumer.config /opt/bitnami/kafka/config/consumer.properties --bootstrap-server kafka:9092 --topic test --from-beginning
```

### Kcat

I found KCat to be quite useful when testing external connections to the 
container.

Config can be stored in `~/.config/kcat.conf`:

```
security.protocol=sasl_plaintext
sasl.mechanism=PLAIN
sasl.username=user
sasl.password=bitnami
```

Or you can pass the config as arguments to your KCat call:

```
kcat -b localhost:9094 -t test -C -X security.protocol=sasl_plaintext -X sasl.mechanism=PLAIN -X sasl.username=user -X sasl.password=bitnami
```
