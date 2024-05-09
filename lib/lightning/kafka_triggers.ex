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
end
