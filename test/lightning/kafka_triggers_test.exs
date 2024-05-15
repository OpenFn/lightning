defmodule Lightning.KafkaTriggersTest do
  use Lightning.DataCase, async: true

  alias Lightning.KafkaTriggers
  alias Lightning.Workflows.Trigger

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
  end
end
