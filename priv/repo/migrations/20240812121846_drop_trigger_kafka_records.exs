defmodule Lightning.Repo.Migrations.DropTriggerKafkaRecords do
  use Ecto.Migration

  def change do
    drop table(:trigger_kafka_messages)
  end
end
