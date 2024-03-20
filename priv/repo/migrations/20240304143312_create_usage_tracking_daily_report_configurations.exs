defmodule Lightning.Repo.Migrations.CreateUsageTrackingDailyReportConfigurations do
  use Ecto.Migration

  def change do
    create table(:usage_tracking_daily_report_configurations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :instance_id, :uuid, null: false
      add :tracking_enabled_at, :utc_datetime_usec, null: true
      add :start_reporting_after, :date, null: true

      timestamps()
    end
  end
end
