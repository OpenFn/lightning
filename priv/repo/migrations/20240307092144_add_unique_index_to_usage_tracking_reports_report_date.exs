defmodule Lightning.Repo.Migrations.AddUniqueIndexToUsageTrackingReportsReportDate do
  use Ecto.Migration

  def change do
    create unique_index(:usage_tracking_reports, [:report_date])
  end
end
