defmodule Lightning.KafkaTriggersTest do
  use Lightning.DataCase, async: true

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  describe ".find_enabled_triggers/0" do
    test "returns enabled kafka triggers" do
      trigger_1 =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: true)
      trigger_2 =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: true)
      not_kafka_trigger =
        insert(:trigger, type: :cron, enabled: true)
      not_enabled =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: false)

      triggers = KafkaTriggers.find_enabled_triggers()

      assert triggers |> contains?(trigger_1)
      assert triggers |> contains?(trigger_2)
      refute triggers |> contains?(not_kafka_trigger)
      refute triggers |> contains?(not_enabled)
    end

    defp contains?(triggers, %Trigger{id: id}) do
      triggers
      |> Enum.any?(& &1.id == id)
    end
  end

  describe ".update_partition_data" do
    setup do
      %{partition: 7, timestamp: 124}
    end

    test "adds data for partition if the trigger has no partition data", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger =
        insert(:trigger, type: :kafka, kafka_configuration: configuration(%{}))

      trigger
      |> KafkaTriggers.update_partition_data(partition, timestamp)

      trigger
      |> assert_persisted_config(%{"#{partition}" => timestamp})
    end

    test "adds data for partition if partition is new but there is data", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(%{"3" => 123})
        )

      trigger
      |> KafkaTriggers.update_partition_data(partition, timestamp)

      trigger
      |> assert_persisted_config(%{
        "3" => 123,
        "#{partition}" => timestamp
      })
    end

    test "does not update partition data if persisted timestamp is newer", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(%{
            "3" => 123,
            "#{partition}" => timestamp + 1
          })
        )

      trigger
      |> KafkaTriggers.update_partition_data(partition, timestamp)

      trigger
      |> assert_persisted_config(%{
        "3" => 123,
        "#{partition}" => timestamp + 1
      })
    end

    test "updates persisted partition data if persisted timestamp is older", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(%{
            "3" => 123,
            "#{partition}" => timestamp - 1
          })
        )

      trigger
      |> KafkaTriggers.update_partition_data(partition, timestamp)

      trigger
      |> assert_persisted_config(%{
        "3" => 123,
        "#{partition}" => timestamp
      })
    end

    defp configuration(partition_timestamps) do
      # TODO Centralise the generation of config to avoid drift
      %{
        "group_id" => "lightning-1",
        "hosts" => [["host-1", 9092], ["other-host-1", 9093]],
        "partition_timestamps" => partition_timestamps,
        "sasl" => nil,
        "ssl" => false,
        "topics" => ["bar_topic"]
      }
    end

    defp assert_persisted_config(trigger, expected_partition_timestamps) do
      reloaded_trigger = Trigger |> Repo.get(trigger.id)

      %Trigger{
        kafka_configuration: %{
          "partition_timestamps" => partition_timestamps
        }
      } = reloaded_trigger

      assert partition_timestamps == expected_partition_timestamps
    end
  end

  describe ".determine_offset_reset_policy" do
    test "returns :earliest if 'earliest'" do
      policy =
        "earliest"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :earliest
    end

    test "returns :latest if 'latest'" do
      policy =
        "latest"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :latest
    end

    test "returns policy if integer (i.e. a timestamp)" do
      timestamp = 1715312900123

      policy =
        timestamp
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == {:timestamp, timestamp}
    end

    test "returns :latest if unrecognised string" do
      policy =
        "woteva"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :latest
    end

    test "returns earliest partition timestamp if data is available" do
      partition_timestamps = %{
        "1" => 1715312900121,
        "2" => 1715312900120,
        "3" => 1715312900123,
      }

      policy =
        "earliest"
        |> build_trigger(partition_timestamps)
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == {:timestamp, 1715312900120}
    end

    defp build_trigger(initial_offset_reset, partition_timestamps \\ %{}) do
      # TODO Centralise the generation of config to avoid drift
      kafka_configuration = %{
        "group_id" => "lightning-1",
        "hosts" => [["host-1", 9092], ["other-host-1", 9093]],
        "initial_offset_reset_policy" => initial_offset_reset,
        "partition_timestamps" => partition_timestamps,
        "sasl" => nil,
        "ssl" => false,
        "topics" => ["bar_topic"]
      }

      build(:trigger, type: :kafka, kafka_configuration: kafka_configuration)
    end
  end

  describe "build_trigger_configuration" do
    setup do
      %{
        group_id: "my_little_group",
        hosts: [["host-1", 9092], ["host-2", 9092]],
        initial_offset_reset_policy: 1715764260123,
        topics: ["my_little_topic"]
      }
    end

    test "returns Kafka trigger configurtion with some defaults", %{
      group_id: group_id,
      hosts: hosts,
      initial_offset_reset_policy: initial_offset_reset_policy,
      topics: topics
    } do
      expected = %{
        "group_id" => group_id,
        "hosts" => hosts,
        "initial_offset_reset_policy" => initial_offset_reset_policy,
        "partition_timestamps" => %{},
        "sasl" => nil,
        "ssl" => false,
        "topics" => topics
      }

      config =
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: initial_offset_reset_policy,
          topics: topics
        )

      assert config == expected
    end

    test "allows sasl and ssl to be set", %{
      group_id: group_id,
      hosts: hosts,
      initial_offset_reset_policy: initial_offset_reset_policy,
      topics: topics
    } do
      sasl = [:plain, "my_user", "my_secret"]
      ssl = true

      expected = %{
        "group_id" => group_id,
        "hosts" => hosts,
        "initial_offset_reset_policy" => initial_offset_reset_policy,
        "partition_timestamps" => %{},
        "sasl" => ["plain", "my_user", "my_secret"],
        "ssl" => true,
        "topics" => topics
      }

      config =
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: initial_offset_reset_policy,
          sasl: sasl,
          ssl: ssl,
          topics: topics
        )

      assert config == expected
    end

    test "converts an initial_offset_reset_policy of :earliest", %{
      group_id: group_id,
      hosts: hosts,
      topics: topics
    } do
      config =
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: :earliest,
          topics: topics
        )

      assert %{"initial_offset_reset_policy" => "earliest"} = config
    end

    test "converts an initial_offset_reset_policy of :latest", %{
      group_id: group_id,
      hosts: hosts,
      topics: topics
    } do
      config =
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: :latest,
          topics: topics
        )

      assert %{"initial_offset_reset_policy" => "latest"} = config
    end

    test "raises on an unrecognised initial_offset_reset_policy", %{
      group_id: group_id,
      hosts: hosts,
      topics: topics
    } do
      assert_raise RuntimeError, ~r/initial_offset_reset_policy/, fn ->
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: :unobtainium,
          topics: topics
        )
      end
    end

    test "raises an error if group_id is not provided", %{
      hosts: hosts,
      initial_offset_reset_policy: initial_offset_reset_policy,
      topics: topics
    } do
      assert_raise KeyError, ~r/group_id/, fn ->
        KafkaTriggers.build_trigger_configuration(
          hosts: hosts,
          initial_offset_reset_policy: initial_offset_reset_policy,
          topics: topics
        )
      end
    end

    test "raises an error if hosts is not provided", %{
      group_id: group_id,
      initial_offset_reset_policy: initial_offset_reset_policy,
      topics: topics
    } do
      assert_raise KeyError, ~r/hosts/, fn ->
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          initial_offset_reset_policy: initial_offset_reset_policy,
          topics: topics
        )
      end
    end

    test "raises an error if initial_offset_reset_policy is not provided", %{
      group_id: group_id,
      hosts: hosts,
      topics: topics
    } do
      assert_raise KeyError, ~r/initial_offset_reset_policy/, fn ->
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          topics: topics
        )
      end
    end

    test "raises an error if topics is not provided", %{
      group_id: group_id,
      hosts: hosts,
      initial_offset_reset_policy: initial_offset_reset_policy
    } do
      assert_raise KeyError, ~r/topics/, fn ->
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: initial_offset_reset_policy
        )
      end
    end
  end

  describe ".build_topic_partition_offset" do
    test "builds based on the proivded message" do
      message = build_broadway_message("foo", 2, 1)
      assert KafkaTriggers.build_topic_partition_offset(message) == "foo_2_1"

      message = build_broadway_message("bar", 4, 2)
      assert KafkaTriggers.build_topic_partition_offset(message) == "bar_4_2"
    end

    defp build_broadway_message(topic, partition, offset) do
      %Broadway.Message{
        data: %{interesting: "stuff"} |> Jason.encode!(),
        metadata: %{
          offset: offset,
          partition: partition,
          key: "",
          headers: [],
          ts: 1715164718283,
          topic: topic
        },
        acknowledger: nil,
        batcher: :default,
        batch_key: {"bar_topic", 2},
        batch_mode: :bulk,
        status: :ok
      }
    end
  end

  describe ".find_message_candidate_sets" do
    test "returns all distinct combinations of trigger, topic, key" do
      trigger_1 = insert(:trigger, type: :kafka)
      trigger_2 = insert(:trigger, type: :kafka)

      message = insert(
        :trigger_kafka_message,
        trigger: trigger_1,
        topic: "topic-1",
        key: "key-1"
      )
      _message_duplicate = insert(
        :trigger_kafka_message,
        trigger: trigger_1,
        topic: "topic-1",
        key: "key-1"
      )
      different_key = insert(
        :trigger_kafka_message,
        trigger: trigger_1,
        topic: "topic-1",
        key: "key-2"
      )
      nil_key = insert(
        :trigger_kafka_message,
        trigger: trigger_1,
        topic: "topic-1",
        key: nil
      )
      different_topic = insert(
        :trigger_kafka_message,
        trigger: trigger_1,
        topic: "topic-2",
        key: "key-1"
      )
      different_trigger = insert(
        :trigger_kafka_message,
        trigger: trigger_2,
        topic: "topic-1",
        key: "key-1"
      )

      sets = KafkaTriggers.find_message_candidate_sets()

      assert sets |> Enum.count() == 5

      assert [%{trigger_id: _, topic: _, key: _} | _other] = sets

      assert sets |> number_of_sets_for(message) == 1
      assert sets |> number_of_sets_for(different_key) == 1
      assert sets |> number_of_sets_for(nil_key) == 1
      assert sets |> number_of_sets_for(different_topic) == 1
      assert sets |> number_of_sets_for(different_trigger) == 1
    end

    def number_of_sets_for(sets, %{trigger: trigger, topic: topic, key: key}) do
      sets
      |> Enum.count(fn
        %{trigger_id: _} = set ->
          set.trigger_id == trigger.id && set.topic == topic && set.key == key
        _ ->
          false
      end)
    end
  end

  describe ".send_after/3" do
    defmodule DummyServer do
      use GenServer

      def start_link(process_to_notify) do
        GenServer.start_link(__MODULE__, process_to_notify)
      end

      @impl true
      def init(process_to_notify) do
        {:ok, process_to_notify}
      end

      @impl true
      def handle_info(:test_message, process_to_notify) do
        Process.send(process_to_notify, :hello_from_dummy, [])
      end
    end

    test "queues a message to be sent after the specified delay" do
      {:ok, target_pid} = DummyServer.start_link(self())

      KafkaTriggers.send_after(target_pid, :test_message, 100)

      assert_receive(:hello_from_dummy, 150)
    end
  end

  describe ".process_candidate_for/1" do
    setup do
      other_message =
        insert(
          :trigger_kafka_message,
          key: "other-key",
          topic: "other-test-topic",
          work_order: nil
        )

      message =
        insert(
          :trigger_kafka_message,
          data: %{triggers: :test} |> Jason.encode!(),
          key: "test-key",
          topic: "test-topic",
          work_order: nil
        )

      candidate_set = %{
          trigger_id: message.trigger.id,
          topic: message.topic,
          key: message.key
      }

      %{
        candidate_set: candidate_set,
        message: message,
        other_message: other_message
      }
    end

    test "returns :ok but does nothing if there is no candidate for the set", %{
      candidate_set: candidate_set,
    } do
      no_such_set = candidate_set |> Map.merge(%{key: "no-such-key"})

      assert KafkaTriggers.process_candidate_for(no_such_set) == :ok
    end

    test "if candidate exists sans work_order, creates work_order", %{
      message: message,
      candidate_set: candidate_set,
    } do
      %{trigger: %{workflow: workflow} = trigger} = message
      project_id = workflow.project_id

      assert KafkaTriggers.process_candidate_for(candidate_set) == :ok

      %{work_order: work_order} =
        TriggerKafkaMessage
        |> Repo.get(message.id)
        |> Repo.preload([
          work_order: [
            :dataclip,
            :runs,
            trigger: [workflow: [:project]],
            workflow: [:project]
          ]
        ])

      assert %WorkOrder {
        dataclip:  %{
          body: %{"triggers" => "test"},
          project_id: ^project_id,
          type: :kafka
        },
        trigger: ^trigger,
        workflow: ^workflow,
      } = work_order
    end
  end

  describe "find_candidate_for/1" do
    setup do
      other_trigger = insert(:trigger)
      trigger = insert(:trigger)

      _other_trigger_set_message_1 =
        insert(
          :trigger_kafka_message,
          trigger: other_trigger,
          key: "set_key",
          topic: "set_topic",
          message_timestamp: 10 |> timestamp_from_offset
        )

      _other_key_set_message_1 =
        insert(
          :trigger_kafka_message,
          trigger: trigger,
          key: "other_set_key",
          topic: "set_topic",
          message_timestamp: 10 |> timestamp_from_offset
        )

      _other_key_set_message_1 =
        insert(
          :trigger_kafka_message,
          trigger: trigger,
          key: "set_key",
          topic: "other_set_topic",
          message_timestamp: 10 |> timestamp_from_offset
        )

      _set_message_2 =
        insert(
          :trigger_kafka_message,
          trigger: trigger,
          key: "set_key",
          topic: "set_topic",
          message_timestamp: 120 |> timestamp_from_offset
        )
      _set_message_3 = 
        insert(
          :trigger_kafka_message,
          trigger: trigger,
          key: "set_key",
          topic: "set_topic",
          message_timestamp: 130 |> timestamp_from_offset
        )
      
      set_message_1 = 
        insert(
          :trigger_kafka_message,
          trigger: trigger,
          key: "set_key",
          topic: "set_topic",
          message_timestamp: 110 |> timestamp_from_offset
        )

      candidate_set = %{
        trigger_id: trigger.id, topic: "set_topic", key: "set_key"
      }

      %{
        candidate_set: candidate_set,
        message: set_message_1
      }
    end

    test "returns nil if it can't find a message for the candidate set", %{
      candidate_set: candidate_set
    } do
      no_such_set = candidate_set |> Map.merge(%{key: "no-such-key"})

      assert KafkaTriggers.find_candidate_for(no_such_set) == nil
    end

    test "returns earliest message - based on message timestamp - for set", %{
      candidate_set: candidate_set,
      message: message
    } do
      message_id = message.id

      assert %TriggerKafkaMessage{
        id: ^message_id
      } = KafkaTriggers.find_candidate_for(candidate_set)
    end

    test "preloads `:workflow`, and `:trigger`", %{
      candidate_set: candidate_set,
    } do
      candidate = KafkaTriggers.find_candidate_for(candidate_set)

      assert %{
        trigger: %Trigger{
          workflow: %Workflow{
          }
        }
      } = candidate
    end

    def timestamp_from_offset(offset) do
      DateTime.utc_now()
      |> DateTime.add(offset)
      |> DateTime.to_unix(:millisecond)
    end
  end
end
