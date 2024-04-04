defmodule Lightning.Repo.Migrations.BackportUsageTrackingSubmissionsStatus do
  use Ecto.Migration

  def change do
    execute """
    UPDATE usage_tracking_reports
    SET submission_status = 'failure'
    WHERE submitted = false AND submission_status IS NULL
    """

    execute """
    UPDATE usage_tracking_reports
    SET submission_status = 'success'
    WHERE submitted = true AND submission_status IS NULL
    """
  end
end
