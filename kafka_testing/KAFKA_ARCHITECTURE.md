# KAFKA ARCHITECTURE

## Overview

Kafka triggers are implemented via `Lightning.Workflows.Trigger` with the
configuration stored as an embedded schema `.kafka_configuration` represented by
`Lightning.Workflows.Trigger.KafkaConfiguration`.

Each kafka trigger instance gets mapped to a BroadwayKafka pipeline. The
pipelines are supervised by `Lightning.KafkaTriggers.PipelineSupervisor`.

When a Trigger is updaed it is added to, removed from or removed from and then
added to the children of the PipelineSupervisor.

Each message received by the pipeline is persisted as a
`Lightning.KafkaTriggers.TriggerKafkaMessage` record. The pipeline also
creates a `Lightning.KafkaTriggers.TriggerKafkaMessageRecord` entry for each
message received. The `TriggerKafkaMessageRecord` entry is to identify and
discard duplicate messages.

In order to ensure that messages that have the same key are processed in order,
we have the Lightning.KafkaTriggers.MessageCandidateSetServer and
Lightning.KafkaTriggers.MessageCandidateSetWorker. These are supervised by the
Lightning.KafkaTriggers.MessageCandidateSetSupervisor.

Most of the logic is currently in Lightning.KafkaTriggers.

Lightning.KafkaTesting.Utils contains some helper functions that may be useful
during testing, but most are obsolete and need to be retired.

## Caveat Developor :)

As of 2024-06-05, the Kafka implementation is still in a very early stage of
testing and should be considered experimental. The code has been tested with
very light loads on a single node Lightning installation running on a
developer's workstation.

The primary risk remains the behaviour of the Lightning/Kafka integration under
conditons closer to those that will be encountered in production scenarios. As
a result, there are a number of sharp edges and affordances that are not present,
and much of the code can do with some housekeeping.

## Detail

### KafkaTriggers.Supervisor

The KafkaTriggers.Supervisor is the top-level supervisor for all the Kafka
functionality. Its starts KafkaTriggers.MessageCandidateSetSupervisor and
KafkaTriggers.PipelineSupervisor as well as KafkaTriggers.EventListener.

It is also responsible for the initial population of pipelines for the
active Kafka triggers.

### KafkaTriggers.Pipeline

Pipeline uses BroadwayKafka to consume messages from Kakfa. It is configured
via child spec generated by KafkaTriggers.generate_pipeline_child_spec/1.

Currently, the configuration uses most of the BoradwayKafka defaults and only
has a single processor. Of note is that BroadwayKafka sends the cluster the
offset commit upon completion of the pipeline, **whether the pipeline completed
successfully or not**. As a result, we must make all efforts to persist the
message before the pipeline completes.

The Pipeline will create a TriggerKafkaMessage record. This serves two purposes:

- We can persist the message simply with as little chance of failure as
  possible.
- The TriggerKafkaMessage helps maintain the sequence of messages with the
  same key within a given topic, by ensuring that a workorder is only
  generated for the first message for a particular key/topic combination.

The Pipeline also creates a TriggerKafkaMessageRecord record. This tracks
the combination of trigger, topic, parition and offset. Each incoming message
is checked for an existing TriggerKafkaMessageRecord that matches and, if so,
the message is discarded.

Errors in message processing (e.g. failure to persist) are handled by marking
the message as failed and then writing some details regarding the message to
the log and to Sentry. No provision for reprocessing the message curently exists.

### KafkaTriggers.MessageCandidateSetSupervisor

The `MessageCandidateSetSupervisor` supervises the `MessageCandidateSetServer`
and the `MessageCandidateSetWorker`. Currently, it starts one of each - while
there can be more than one `MessageCandidateSetWorker`, there should only be
a single `MessageCandidateSetServer`.

### KafkaTriggers.MessageCandidateSetServer

A `MessageCandidateSet` is the collection of TriggerKafkaMessage records that
all have the same trigger_id, topic and key. Each unique combination of
trigger_id, topic and key is defined as `MessageCandidateSet` (**MCS**) instance.

The `MessageCandidateSetServer` is reponsible for finding all the unique
MCSs within the persisted `TriggerKafkaMessage` records and providing these,
one at a time to the `MessageCandidateSetWorker` when requested.

On the first request for an MCS after the `MessageCandidateSetServer` has
started, the `MessageCandidateSetServer` will retrive all distinct MCSs from
the database and store these in memory. It will serve from memory until the list
has been exhausted, whereupon it will, once again, retrieve all distinct MCSs
from the database.

### KafkaTriggers.MessageCandidateSetWorker

When a `MessageCandidateSetWorker` is started, it will  `enqueue` a message to
itself using `Process.send_after`. Upon receipt of this message, it will
request a MCS from the `MessageCandidateSetServer`.

If a MCS is returned, the `MessageCandidateSetWorker` will attempt to find
a MessageCandidateSetCandidate for the MCS. The `MessageCandidateSetCandidate`
is the earliest TriggerKafkaMessage record for the given MCS, based on
message offset.

If a `MessageCandidateSetCandidate` is found, the `MessageCandidateSetWorker`
will follow one of three paths:

- If the `MessageCandidateSetCandidate` is not associated with a `WorkOrder` it
  will generate a `WorkOrder` and associate it with the TriggerKafkaMessage
  record.
- If the `MessageCandidateSetCandidate` is associated with a `WorkOrder` that
  has not completed successfully, it will take no further action. This may
  result in a MessageCanidateSet being blocked if the `WorkOrder` never
  completes successfully. Work is still required on a way to make this
  visible to the user, so that an unblocking action can be performed.
- If the `MessageCandidateSetCandidate` is associated with a `WorkOrder` that
  has completed successfully, the TriggerKafkaMessage record will be deleted.

Once the `MessageCandidateSetWorker` has completed processing the MCS, it
will `enqueue` a message to itself using `Process.send_after` to request the
next MCS.

Before a `MessageCandidateSetWorker` interacts with a
`MessageCandidateSetCandidate` it will attempt to lock the TriggerKafkaMessage
record. If this fails, the `MessageCandidateSetWorker` will assume that another
worker is busy with the MessageCandidateSet it will request the next MCSID.

If the `MessageCandidateSetWorker` is unable to find a
`MessageCandidateSetCandidate` for a given MCS or if it does not get an MCS
it will `enqueue` a message to itself using `Process.send_after` to request
another MCS.

### Workflows.Trigger.KafkaConfiguration

`KafkaConfiguration` is a wrapper around the configuration for a Kafka trigger
and, as such, many of its fields are fairly self-explanatory, with two
exceptions:

`initial_offset_reset_policy` determines what happens when a new consumer group
connects to a topic and there is no committed offset. It can have three possible
values `earliest` (start from the earliest message in the topic),
`latest` (start from the latest message in the topic) or a UNIX timestamp
with millsecond precision. If a timestamp is given the cluster will attempt to
start from the message with the offset closest to the timestamp. Using a
timestamp may be useful for migration scenarios but is has not been tested
outside of a local Kafka cluster so more testing is required.

`partition_timestamps` this tracks the last timestamp for each partition. It is
hoped that this will be useful for cases where a trigger has been disabled for
so long that the cluster no longer retains a committed offset for the consumer
group. In this case, the offset provided when the consumer group starts will
be the ealiest of the timestamps across all partitions rather than what
was provided in `initial_offset_reset_policy`.

### Workflows

`Workflows.save_workflow/1` has been extended to call
`Triggers.Events.kafka_trigger_updated` if any kafka triggers form part of the
workflow changes.

The event that is published will be received by `KafkaTriggers.EventListener`.

### KafkaTriggers.EventListener

The `KafkaTriggers.EventListener` listens for events relating to changes to
Kafka trigges and it will update/dd or remove the BroadayKafka pipeline that
is associated with the affected trigger.

## Testing

### Additional test tooling

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

### Viewing triggers that are currently active

```
GenServer.whereis(:kafka_pipeline_supervisor) |> Supervisor.which_children()
```

### Testing locally using the docker Kafka cluster

Create a network so that the cluster can communicate amongst themselves:

```
docker network create kafka-network
```

Start the cluster. Note: The `KAFKA_MEMORY_LIMIT` and `KAFKA_MEMORY_RESERVE`
are set to 1000M, but these should be adjusted to a value that is appropriate
for your system.

```
KAFKA_MEMORY_LIMIT=1000M KAFKA_MEMORY_RESERVE=1000M KAFKA_DEBUG=false docker-compose -f kafka_testing/docker-compose.kafka-testing-cluster.yml up -d
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
cat message.json | kcat -P -b 127.0.0.1:9094 -t baz_topic
```

The above example is connecting to the Kafka node that exposes port 9094,
but ports 9095 or 9096 can alse be used. If time allows, I will script
a way to automate the population of topics.

Once these are setup, you can create a Kafka trigger via the UI.

You will need to specify the following:

```
Hosts: localhost:9094, localhost:9095, localhost:9096
Topic: Can be any *one* of foo_topic, bar_topic, baz_topic, boz_topic
Group ID: Can be anything, as long as it is unique.
Initial offset reset policy: earliest
SSL: Unselected
SASL Authentication: None
Username: Leave blank
Passord: Leave blank.
```

#### Cluster troubleshooting

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

### Testing using a Confluent Cloud instance

At the time of writing, Confluent Cloud offered a certain number of credits
for new users which can be used to run a local instance. You do need to provide
your credit card details (le sigh), but thus far my usage has been low enough
so that I still have the same number of credits as when I started.

Confluent Cloud is useful for testing SASL authentication and SSL and can
serve as a sanity check.

As Confluent Cloud requires authentication, the most convenient way to use it
with `kcat` is to create a config file at `~/.config/kcat.conf`:

```
bootstrap.servers=my-host.us-west2.gcp.confluent.cloud:9092
security.protocol=sasl_ssl
sasl.mechanism=PLAIN
sasl.username=your-username
sasl.password=your-password
session.timeout.ms=45000
```

Assuming you have created a topic on your Confluent Cloud instance, named
`baz-topic`, you can produce a message using the below:

```
cat message.json | kcat -P -t baz_topic
```

When creating a Trigger via the UI, you will need to select SSL and set
`SASL Authentication`, `Username` and `Password` based on what Confluent
provides.

Confluent provides a nice UI which is useful for setting up topics or
producing the occasional message.
