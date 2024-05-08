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

  def update_partition_data(_trigger, _partition, _timestamp) do
    %Trigger{
      kafka_configuration: existing_kafka_configuration
    } = trigger

    updated_kafka_configuration =
      existing_kafka_configuration
      |> Map.merge(%{"partition_timestamps" => %{"#{partition}" => timestamp}})

  end
end
