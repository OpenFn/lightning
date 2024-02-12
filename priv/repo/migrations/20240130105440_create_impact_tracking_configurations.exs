defmodule Lightning.Repo.Migrations.CreateImpactTrackingConfigurations do
  use Ecto.Migration

  def change do
    create table(:impact_tracking_configurations, primary_key: false) do
      add :instance_id, :uuid, null: false

      timestamps()
    end
  end
end
