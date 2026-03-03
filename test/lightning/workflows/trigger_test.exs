defmodule Lightning.Workflows.TriggerTest do
  use Lightning.DataCase, async: true

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

    test "sets webhook_reply to nil when type is :cron" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          webhook_reply: :before_start
        })

      assert get_field(changeset, :webhook_reply) == nil

      # Also when converting from webhook to cron
      changeset =
        Trigger.changeset(
          %Trigger{type: :webhook, webhook_reply: :after_completion},
          %{type: :cron}
        )

      assert get_field(changeset, :webhook_reply) == nil
    end

    test "sets webhook_reply to nil when type is :kafka" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka,
          webhook_reply: :custom,
          kafka_configuration: %{
            group_id: "group_id",
            hosts: [["host1", "9092"]],
            hosts_string: "host1:9092",
            initial_offset_reset_policy: "earliest",
            sasl: "plain",
            ssl: true,
            topics: ["foo"],
            topics_string: "foo"
          }
        })

      assert get_field(changeset, :webhook_reply) == nil

      # Also when converting from webhook to kafka
      changeset =
        Trigger.changeset(
          %Trigger{type: :webhook, webhook_reply: :before_start},
          %{
            type: :kafka,
            kafka_configuration: %{
              group_id: "group_id",
              hosts: [["host1", "9092"]],
              hosts_string: "host1:9092",
              initial_offset_reset_policy: "earliest",
              sasl: "plain",
              ssl: true,
              topics: ["foo"],
              topics_string: "foo"
            }
          }
        )

      assert get_field(changeset, :webhook_reply) == nil
    end

    test "allows webhook_reply to be set for webhook triggers" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          webhook_reply: :after_completion
        })

      assert get_field(changeset, :webhook_reply) == :after_completion

      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          webhook_reply: :custom
        })

      assert get_field(changeset, :webhook_reply) == :custom
    end
  end
end
