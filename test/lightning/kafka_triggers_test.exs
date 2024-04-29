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
end
