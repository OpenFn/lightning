defmodule Lightning.Repo.Migrations.CreateImpactTrackingReportsTable do
  use Ecto.Migration

  def change do
    create table(:impact_tracking_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :data, :map, null: false
      add :submitted, :boolean, default: false
      add :submitted_at, :utc_datetime_usec, null: true

      timestamps()
    end
  end
end
