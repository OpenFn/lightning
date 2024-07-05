defmodule Lightning.Workflows.TriggerTest do
  use Lightning.DataCase, async: true

  alias Ecto.Changeset
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers.KafkaConfiguration

  describe "changeset/2" do
    test "type must be valid" do
      errors = Trigger.changeset(%Trigger{}, %{type: :foo}) |> errors_on()
      assert errors[:type] == ["is invalid"]

      errors = Trigger.changeset(%Trigger{}, %{type: :webhook}) |> errors_on()
      assert errors[:type] == nil
    end

    test "must raise an error when cron expression is invalid" do
      errors =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: "this_is_not_a_cron_valid_cron_expression"
        })
        |> errors_on()

      assert errors[:cron_expression] == [
               "Can't parse this_is_not_a_cron_valid_cron_expression as minute."
             ]
    end

    test "must raise no error when cron expression is valid" do
      errors =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: "* * * *"
        })
        |> errors_on()

      assert errors[:cron_expression] == nil
    end

    test "removes cron expression job when type is :webhook" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          cron_expression: "* * * *"
        })

      assert get_field(changeset, :cron_expression) == nil

      changeset =
        Trigger.changeset(
          %Trigger{type: :cron, cron_expression: "* * * *"},
          %{
            type: :webhook
          }
        )

      assert get_field(changeset, :cron_expression) == nil
    end

    test "allows creation of kafka trigger" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka,
          kafka_configuration: %{
            group_id: "group_id",
            hosts: [
              ["host1", "9092"],
              ["host2", "9093"]
            ],
            hosts_string: "host1:9092, host2:9093",
            initial_offset_reset_policy: "earliest",
            partition_timestamps: %{"1" => 1_717_174_749_123},
            password: "password",
            sasl: "plain",
            ssl: true,
            topics: ["foo", "bar"],
            topics_string: "foo, bar",
            username: "username"
          }
        })

      assert %{valid?: true} = changeset
    end

    test "removes cron expression job when type is :kafka" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka,
          cron_expression: "* * * *"
        })

      assert get_field(changeset, :cron_expression) == nil

      changeset =
        Trigger.changeset(
          %Trigger{type: :cron, cron_expression: "* * * *"},
          %{
            type: :kafka
          }
        )

      assert get_field(changeset, :cron_expression) == nil
    end

    test "is invalid if type is :kafka but kafka_configuration is not set" do
      errors =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka
        })
        |> errors_on()

      assert errors[:kafka_configuration] == ["can't be blank"]
    end

    test "removes kafka config when type is :webhook" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          kafka_configuration: %{a: :b}
        })

      assert get_field(changeset, :kafka_configuration) == nil

      changeset =
        Trigger.changeset(
          %Trigger{
            type: :kafka,
            kafka_configuration: %KafkaConfiguration{group_id: "foo"}
          },
          %{
            type: :webhook
          }
        )

      assert get_field(changeset, :kafka_configuration) == nil
    end

    test "removes kafka config when type is :cron" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          kafka_configuration: %{a: :b}
        })

      assert get_field(changeset, :kafka_configuration) == nil

      changeset =
        Trigger.changeset(
          %Trigger{
            type: :kafka,
            kafka_configuration: %KafkaConfiguration{group_id: "foo"}
          },
          %{
            type: :cron
          }
        )

      assert get_field(changeset, :kafka_configuration) == nil
    end
  end

  describe ".kafka_partitions_changeset/3" do
    setup do
      %{partition: 7, timestamp: 124}
    end

    test "returns a kafka configuration changeset if type is kafka", %{
      partition: partition,
      timestamp: timestamp
    } do
      kafka_configuration =
        build(:triggers_kafka_configuration, partition_timestamps: %{})
      trigger =
        insert(:trigger, type: :kafka, kafka_configuration: kafka_configuration)

      expected_timestamps = %{
        "#{partition}" => timestamp
      }

      changeset =
        trigger
        |> Trigger.kafka_partitions_changeset(partition, timestamp)

      assert %Changeset{data: ^trigger, changes: changes} = changeset

      assert %{
               kafka_configuration: %{
                 changes: %{partition_timestamps: ^expected_timestamps}
               }
             } = changes
    end

    test "returns an empty changeset if type is :webhook", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger = insert(:trigger, type: :webhook)

      changeset =
        trigger
        |> Trigger.kafka_partitions_changeset(partition, timestamp)

      assert %Changeset{data: ^trigger, changes: changes} = changeset

      assert changes == %{}
    end

    test "returns an empty changeset if type is :cron", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger = insert(:trigger, type: :cron)

      changeset =
        trigger
        |> Trigger.kafka_partitions_changeset(partition, timestamp)

      assert %Changeset{data: ^trigger, changes: changes} = changeset

      assert changes == %{}
    end
  end
end
