defmodule Lightning.Repo.Migrations.CreateTriggerKafkaMessages do
  use Ecto.Migration

  def change do
    create table(:trigger_kafka_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :trigger_id, references(:triggers, type: :binary_id), null: false
      add :work_order_id, references(:work_orders, type: :binary_id), null: true
      add :topic, :string, null: false
      add :key, :string, null: true
      add :message_timestamp, :bigint, null: false
      add :metadata, :map, null: false
      add :data, :binary, null: false

      timestamps()
    end
  end
end
