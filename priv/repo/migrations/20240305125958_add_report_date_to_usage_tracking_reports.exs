defmodule Lightning.Repo.Migrations.AddReportDateToUsageTrackingReports do
  use Ecto.Migration

  def change do
    alter table(:usage_tracking_reports) do
      add :report_date, :date, null: true
    end
  end
end
