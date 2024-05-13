defmodule Lightning.Repo.Migrations.CreateTriggerKafkaMessageRecords do
  use Ecto.Migration

  def change do
    create table(:trigger_kafka_message_records, primary_key: false) do
      add :trigger_id, references(:triggers, type: :binary_id), null: false, primary_key: true
      add :topic_partition_offset, :string, null: false, primary_key: true

      timestamps(updated_at: false)
    end
  end
end
