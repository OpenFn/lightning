defmodule Lightning.Repo.Migrations.AddKafkaConfigurationToTriggers do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :kafka_configuration, :map, default: %{}, null: false
    end
  end
end
