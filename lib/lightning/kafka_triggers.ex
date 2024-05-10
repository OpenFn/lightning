defmodule Lightning.KafkaTriggers do
  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Workflows.Trigger

  def find_enabled_triggers do
    query =
      from t in Trigger,
      where: t.type == :kafka,
      where: t.enabled == true

    query |> Repo.all()
  end

  def update_partition_data(trigger, partition, timestamp) do
    partition_key = partition |> Integer.to_string()

    %Trigger{
      kafka_configuration: existing_kafka_configuration
    } = trigger

    %{
      "partition_timestamps" => partition_timestamps
    } = existing_kafka_configuration

    updated_partition_timestamps =
      partition_timestamps
      |> case do
        existing = %{^partition_key => existing_timestamp} when existing_timestamp < timestamp ->
          existing |> Map.merge(%{partition_key => timestamp})
        existing = %{^partition_key => _existing_timestamp} ->
          existing
        existing ->
          existing |> Map.merge(%{partition_key => timestamp})
      end

    updated_kafka_configuration =
      existing_kafka_configuration
      |> Map.merge(%{"partition_timestamps" => updated_partition_timestamps})

    trigger
    |> Trigger.changeset(%{kafka_configuration: updated_kafka_configuration})
    |> Repo.update()
  end

  def determine_offset_reset_policy(trigger) do
    %Trigger{kafka_configuration: kafka_configuration} = trigger

    case kafka_configuration do
      config = %{"partition_timestamps" => ts} when map_size(ts) == 0 ->
        initial_policy(config)
      %{"partition_timestamps" => ts} ->
        earliest_timestamp(ts)
    end
  end

  defp initial_policy(%{"initial_offset_reset_policy" => initial_policy}) do
    case initial_policy do
      policy when is_integer(policy) -> policy
      policy when policy in ["earliest", "latest"] -> policy |> String.to_atom()
      _unrecognised_policy -> :latest
    end
  end

  defp earliest_timestamp(timestamps) do
    timestamps |> Map.values() |> Enum.sort |> hd()
  end
end
