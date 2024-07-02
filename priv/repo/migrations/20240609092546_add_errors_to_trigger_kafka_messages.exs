defmodule Lightning.Repo.Migrations.AddProcessingDataToTriggerKafkaMessages do
  use Ecto.Migration

  def change do
    alter table(:trigger_kafka_messages) do
      add :processing_data, :map, default: %{}
    end
  end
end
