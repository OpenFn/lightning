defmodule Lightning.Repo.Migrations.AddKafkaConfigurationToTriggers do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :kafka_configuration, :map, null: true
    end
  end
end
