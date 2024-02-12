defmodule Lightning.Repo.Migrations.RenameImpactTrackingTablesToUsageTracking do
  use Ecto.Migration

  def up do
    rename table(:impact_tracking_configurations), to: table(:usage_tracking_configurations)
    rename table(:impact_tracking_reports), to: table(:usage_tracking_reports)

    execute("ALTER INDEX impact_tracking_reports_pkey RENAME TO usage_tracking_reports_pkey")
  end

  def down do
    rename table(:usage_tracking_configurations), to: table(:impact_tracking_configurations)
    rename table(:usage_tracking_reports), to: table(:impact_tracking_reports)

    execute("ALTER INDEX usage_tracking_reports_pkey RENAME TO impact_tracking_reports_pkey")
  end
end
