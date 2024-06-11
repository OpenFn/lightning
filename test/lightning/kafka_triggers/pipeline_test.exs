defmodule Lightning.KafkaTriggers.PipelineTest do
  use Lightning.DataCase

  import Mock

  alias Ecto.Changeset
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.KafkaTriggers.Pipeline
  alias Lightning.Repo
  alias Lightning.Workflows.Trigger

  describe ".start_link/1" do
    test "starts a Broadway GenServer process with SASL credentials" do
      group_id = "my_group"
      hosts = [{"localhost", 9092}]
      offset_reset_policy = :latest
      sasl = {:plain, "my_username", "my_secret"}
      sasl_expected = {:plain, "my_username", "my_secret"}
      ssl = true
      topics = ["my_topic"]
      trigger_id = :my_trigger_id

      with_mock Broadway,
        start_link: fn _module, _opts -> {:ok, "fake-pid"} end do
        Pipeline.start_link(
          group_id: group_id,
          hosts: hosts,
          offset_reset_policy: offset_reset_policy,
          sasl: sasl,
          ssl: ssl,
          topics: topics,
          trigger_id: trigger_id
        )

        assert called(
                 Broadway.start_link(
                   Pipeline,
                   name: trigger_id,
                   context: %{
                     trigger_id: trigger_id
                   },
                   producer: [
                     module: {
                       BroadwayKafka.Producer,
                       [
                         client_config: [
                           sasl: sasl_expected,
                           ssl: ssl,
                           connect_timeout: 30000
                         ],
                         hosts: hosts,
                         group_id: group_id,
                         topics: topics,
                         offset_reset_policy: offset_reset_policy
                       ]
                     },
                     concurrency: 1
                   ],
                   processors: [
                     default: [
                       concurrency: 10
                     ]
                   ],
                   batchers: []
                 )
               )
      end
    end

    test "starts a Broadway GenServer process without SASL credentials" do
      group_id = "my_group"
      hosts = [{"localhost", 9092}]
      offset_reset_policy = :latest
      sasl = nil
      ssl = true
      topics = ["my_topic"]
      trigger_id = :my_trigger_id

      with_mock Broadway,
        start_link: fn _module, _opts -> {:ok, "fake-pid"} end do
        Pipeline.start_link(
          group_id: group_id,
          hosts: hosts,
          offset_reset_policy: offset_reset_policy,
          sasl: sasl,
          ssl: ssl,
          topics: topics,
          trigger_id: trigger_id
        )

        assert called(
                 Broadway.start_link(
                   Pipeline,
                   name: trigger_id,
                   context: %{
                     trigger_id: trigger_id
                   },
                   producer: [
                     module: {
                       BroadwayKafka.Producer,
                       [
                         client_config: [ssl: ssl, connect_timeout: 30000],
                         hosts: hosts,
                         group_id: group_id,
                         topics: topics,
                         offset_reset_policy: offset_reset_policy
                       ]
                     },
                     concurrency: 1
                   ],
                   processors: [
                     default: [
                       concurrency: 10
                     ]
                   ],
                   batchers: []
                 )
               )
      end
    end
  end

  describe ".handle_message" do
    setup do
      trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 1),
          enabled: true
        )

      trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 2, ssl: false),
          enabled: true
        )

      context = %{trigger_id: trigger_1.id |> String.to_atom()}

      %{trigger_1: trigger_1, trigger_2: trigger_2, context: context}
    end

    test "returns the message", %{context: context} do
      message = build_broadway_message()

      assert Pipeline.handle_message(nil, message, context) == message
    end

    test "updates the partition timestamp for the trigger", %{
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      context: context
    } do
      message = build_broadway_message()

      Pipeline.handle_message(nil, message, context)

      %{
        kafka_configuration: %{
          partition_timestamps: trigger_1_timestamps
        }
      } = Trigger |> Repo.get(trigger_1.id)

      %{
        kafka_configuration: %{
          partition_timestamps: trigger_2_timestamps
        }
      } = Trigger |> Repo.get(trigger_2.id)

      assert %{"1" => 1_715_164_718_281, "2" => 1_715_164_718_283} =
               trigger_1_timestamps

      assert trigger_2_timestamps == partition_timestamps()
    end

    test "persists a TriggerKafkaMessage for further processing", %{
      context: context
    } do
      trigger_id = Atom.to_string(context.trigger_id)

      message = build_broadway_message()

      Pipeline.handle_message(nil, message, context)

      trigger_kafka_message = Repo.one(TriggerKafkaMessage)

      metadata = message.metadata |> stringify_keys()
      data = message.data

      assert %{
               data: ^data,
               key: "abc_123_def",
               message_timestamp: 1_715_164_718_283,
               metadata: ^metadata,
               offset: 11,
               topic: "bar_topic",
               trigger_id: ^trigger_id,
               work_order_id: nil
             } = trigger_kafka_message
    end

    test "converts empty Kafka key to nil TriggerKafkaMessage key", %{
      context: context
    } do
      message = build_broadway_message("")

      Pipeline.handle_message(nil, message, context)

      trigger_kafka_message = Repo.one(TriggerKafkaMessage)

      assert %{key: nil} = trigger_kafka_message
    end

    test "records the message for the purposes of future deduplication", %{
      context: context
    } do
      trigger_id = context.trigger_id |> Atom.to_string()

      message = build_broadway_message()

      Pipeline.handle_message(nil, message, context)

      message_record = Repo.one(TriggerKafkaMessageRecord)

      assert %TriggerKafkaMessageRecord{
               trigger_id: ^trigger_id,
               topic_partition_offset: "bar_topic_2_11"
             } = message_record
    end

    test "does not update partition timestamps if message is duplicate", %{
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      context: context
    } do
      trigger_id = context.trigger_id |> Atom.to_string()

      message = build_broadway_message()

      insert_message_record(trigger_id)

      Pipeline.handle_message(nil, message, context)

      %{
        kafka_configuration: %{
          partition_timestamps: trigger_1_timestamps
        }
      } = Trigger |> Repo.get(trigger_1.id)

      %{
        kafka_configuration: %{
          partition_timestamps: trigger_2_timestamps
        }
      } = Trigger |> Repo.get(trigger_2.id)

      assert trigger_1_timestamps == partition_timestamps()
      assert trigger_2_timestamps == partition_timestamps()
    end

    test "does not create TriggerKafkaMessage if message is duplicate", %{
      context: context
    } do
      trigger_id = context.trigger_id |> Atom.to_string()

      message = build_broadway_message()

      insert_message_record(trigger_id)

      Pipeline.handle_message(nil, message, context)

      assert Repo.one(TriggerKafkaMessage) == nil
    end

    test "raises error on non-duplicate TriggerKafkaMessageRecord save error", %{
      context: context
    } do
      message = build_broadway_message()

      Pipeline.handle_message(nil, message, context)

      with_mock Repo,
        insert: fn _ -> {:error, %Changeset{}} end do
        assert_raise RuntimeError, ~r/Unhandled error/, fn ->
          Pipeline.handle_message(nil, message, context)
        end
      end
    end

    defp build_broadway_message(key \\ "abc_123_def") do
      %Broadway.Message{
        data: %{interesting: "stuff"} |> Jason.encode!(),
        metadata: %{
          offset: 11,
          partition: 2,
          key: key,
          headers: [],
          ts: 1_715_164_718_283,
          topic: "bar_topic"
        },
        acknowledger: nil,
        batcher: :default,
        batch_key: {"bar_topic", 2},
        batch_mode: :bulk,
        status: :ok
      }
    end

    defp configuration(opts) do
      index = opts |> Keyword.get(:index)
      sasl = opts |> Keyword.get(:sasl, true)
      ssl = opts |> Keyword.get(:ssl, true)

      password = if sasl, do: "secret-#{index}", else: nil
      sasl_type = if sasl, do: :plain, else: nil
      username = if sasl, do: "my-user-#{index}", else: nil

      %{
        group_id: "lightning-#{index}",
        hosts: [["host-#{index}", "9092"], ["other-host-#{index}", "9093"]],
        hosts_string: "host-#{index}:9092, other-host-#{index}:9093",
        initial_offset_reset_policy: "earliest",
        partition_timestamps: partition_timestamps(),
        password: password,
        sasl: sasl_type,
        ssl: ssl,
        topics: ["topic-#{index}-1", "topic-#{index}-2"],
        topics_string: "topic-#{index}-1, topic-#{index}-2",
        username: username
      }
    end

    defp partition_timestamps do
      %{
        "1" => 1_715_164_718_281,
        "2" => 1_715_164_718_282
      }
    end

    defp insert_message_record(trigger_id) do
      TriggerKafkaMessageRecord.changeset(
        %TriggerKafkaMessageRecord{},
        %{
          topic_partition_offset: "bar_topic_2_11",
          trigger_id: trigger_id
        }
      )
      |> Repo.insert()
    end

    # Put this in a helper
    defp stringify_keys(map) do
      map
      |> Map.keys()
      |> Enum.reduce(%{}, fn key, acc ->
        acc |> stringify_key(key, map[key])
      end)
    end

    defp stringify_key(acc, key, val) when is_map(val) and not is_struct(val) do
      acc
      |> Map.merge(%{to_string(key) => stringify_keys(val)})
    end

    defp stringify_key(acc, key, val) do
      acc
      |> Map.merge(%{to_string(key) => val})
    end
  end
end
