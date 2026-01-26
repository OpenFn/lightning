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
  end

  describe "webhook_reply_for_json/1" do
    test "returns webhook_reply value for webhook triggers" do
      trigger = %Trigger{type: :webhook, webhook_reply: :before_start}
      assert Trigger.webhook_reply_for_json(trigger) == :before_start

      trigger = %Trigger{type: :webhook, webhook_reply: :after_completion}
      assert Trigger.webhook_reply_for_json(trigger) == :after_completion

      trigger = %Trigger{type: :webhook, webhook_reply: :custom}
      assert Trigger.webhook_reply_for_json(trigger) == :custom
    end

    test "returns nil for cron triggers regardless of database value" do
      trigger = %Trigger{type: :cron, webhook_reply: :before_start}
      assert Trigger.webhook_reply_for_json(trigger) == nil
    end

    test "returns nil for kafka triggers regardless of database value" do
      trigger = %Trigger{type: :kafka, webhook_reply: :before_start}
      assert Trigger.webhook_reply_for_json(trigger) == nil
    end
  end

  describe "Jason.Encoder implementation" do
    test "encodes webhook triggers with webhook_reply value" do
      trigger = %Trigger{
        id: Ecto.UUID.generate(),
        type: :webhook,
        enabled: true,
        webhook_reply: :before_start
      }

      {:ok, json} = Jason.encode(trigger)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "webhook"
      assert decoded["webhook_reply"] == "before_start"
    end

    test "encodes cron triggers with webhook_reply as nil" do
      trigger = %Trigger{
        id: Ecto.UUID.generate(),
        type: :cron,
        enabled: true,
        cron_expression: "0 0 * * *",
        webhook_reply: :before_start
      }

      {:ok, json} = Jason.encode(trigger)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "cron"
      assert decoded["cron_expression"] == "0 0 * * *"
      assert decoded["webhook_reply"] == nil
    end

    test "encodes kafka triggers with webhook_reply as nil" do
      trigger = %Trigger{
        id: Ecto.UUID.generate(),
        type: :kafka,
        enabled: true,
        webhook_reply: :before_start
      }

      {:ok, json} = Jason.encode(trigger)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "kafka"
      assert decoded["webhook_reply"] == nil
    end
  end
end
