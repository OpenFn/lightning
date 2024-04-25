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

## Testing using the Kafka cluster(recommended)

Create a network so that the cluster can communicate amongst themselves:

```
docker network create kafka-network
```

Start the cluster:

```
docker-compose -f kafka_testing/docker-compose.kafka-testing-cluster.yml up -d
```

The cluster does not auto-provision topics as I found that it does not seem
to play nicely with the cluster (it is probably possible to configure this away).

Before testing, you will need to create the topics on the cluster. This can be
done from any of the three Kafka nodes, by running the following commands from
within the container:

```
kafka-topics.sh --bootstrap-server localhost:9092 --create --topic foo_topic --partitions=3 --replication-factor=3
kafka-topics.sh --bootstrap-server localhost:9092 --create --topic bar_topic --partitions=3 --replication-factor=3
kafka-topics.sh --bootstrap-server localhost:9092 --create --topic baz_topic --partitions=3 --replication-factor=3
kafka-topics.sh --bootstrap-server localhost:9092 --create --topic boz_topic --partitions=3 --replication-factor=3
```

If the command produces an error containing the text
'The target replication factor of 3 cannot be reached because only 2 broker(s) are registered',
that is an indication that the cluster is not properly configured (see the
cluster troubleshooting section below).

To validate that everything is working correctly, run the following from a
**different** Kafka node:

```
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

This should list all the topics that you just created.

Now, you can produce message for the topic - this can be done via
`kafka_console-producer.sh` as detailed elsewhere or you could use kcat:

```
echo "High-4 Baz" | kcat -P -b 127.0.0.1:9094 -t baz_topic
```

The above example is connecting to the Kafka node that exposes port 9094,
but ports 9095 or 9096 can alse be used. If time allows, I will script
a way to automate the population of topics.

You can then run `kafka_testing/kafka_testing.exs`.

### Cluster troubleshooting

Most of the issues I have had so far have been due to configuration issues.
Hopefully, the current container configuration should 'just work'.

If you are not seeing topics show up on other nodes in the cluster, you
can check if the basic netowrk plumbing is working by seeing if you
can connect to other nodes and list their topics. 

For example, if kafka-05 is not reflecting the topics but you can see that
the topic exists on kafka-04, you can run the below from kafka-05:

```
kafka-topics.sh --bootstrap-server kafka-04:9092 --list
```

If that returns the expected list of topics, you know that the basic network
topology is working. If the netwrok is not working it should complain about an
unknown host and you should also see an error if you have specified the
incorrect port (e.g. you think kafka-04 is listening to port 9092, but it has
been configured for 9091).

If you make a syntax error when populating `KAFKA_CFG_LISTENERS`, that can
result in the node not being able to communicate - check the syntax carefully.

Another configuration setting to check is `KAFKA_CFG_CONTROLLER_QUORUM_VOTERS`.
This should include all the nodes in the cluster and it should be the same for
all nodes. You may need to check this if you get the
'only ... broker(s) are registered' error or you see that not all the nodes
are getting the topics.

If you are having issues producing to one topic, but the other topics seem to
be ok, you can view the topic in detail:

```
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic foo_topic
```

The output should be similar to the below:

```
Topic: foo_topic	TopicId: lCC4UrNqRB2pXzjuHOvXxA	PartitionCount: 3	ReplicationFactor: 3	Configs: segment.bytes=1073741824
	Topic: foo_topic	Partition: 0	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2
	Topic: foo_topic	Partition: 1	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: foo_topic	Partition: 2	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
```

While testing I had a problematic topic where the `Leader` was listed as `None`. I had to
delete the topic using: 

```
kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic foo_topic
```

And then I had to recreate it using `--create`.

## Testing using the supervisor testing script and a single node

Note: `kafka-testing.exs` has been modified to support testing against a
Kafka cluster rather than a single instance.  If you wish to run it 
against a single instance, modify it per the instructions inside the script.

`kafka_testing/kafka_testing.exs` is a script that will run for 5 or 6 minutes and subscribe
to multiple topics (4) on a local kakfa container
(kafka_testing/docker-compose-kafka-testing-2.yml).

It uses a combination of starting pipelines as well as one pipeline that is
added after the supervisor has been started.

Before running the script, you will need to populate each of the test topics
(`foo_topic`, `bar_topic`, `baz_topic` and `boz_topic`). This can be done by
runnig the below (I would suggest running each command in a separate terminal
tab or session):

```
docker exec -it lightning_kafka-01_1 kafka-console-producer.sh --producer.config /opt/bitnami/kafka/config/producer.properties --bootstrap-server kafka-01:9092 --topic foo_topic
docker exec -it lightning_kafka-01_1 kafka-console-producer.sh --producer.config /opt/bitnami/kafka/config/producer.properties --bootstrap-server kafka-01:9092 --topic bar_topic
docker exec -it lightning_kafka-01_1 kafka-console-producer.sh --producer.config /opt/bitnami/kafka/config/producer.properties --bootstrap-server kafka-01:9092 --topic baz_topic
docker exec -it lightning_kafka-01_1 kafka-console-producer.sh --producer.config /opt/bitnami/kafka/config/producer.properties --bootstrap-server kafka-01:9092 --topic boz_topic
```

Once it is running, it should output evidence of messages being received.

## Test containers

There are two docker-compose files available for test purposes. 

- `kafka_testing/docker-compose.kafka-testing.yml` - this starts up a single Kafka node
  running Zookeeper and uses SASL authentication in addition to a
  non-authenticated broekr.
- `kafka_testing/docker-compose-kafka-testing-2.yml` - this starts up a single Kafka node
  running KRaft and does not use authentication.

In the subsections below, I will refer to the above as the Zookeeper and KRaft
instances respectively.

### Zookeeper Container

To start the Zookeeper container, run:

```
docker-compose -f kafka_testing/docker-compose.kafka-testing.yml up -d
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

### KRaft container

To start the Kraft container, run:

```
docker-compose -f kafka_testing/docker-compose.kafka-testing-2.yml up -d
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
