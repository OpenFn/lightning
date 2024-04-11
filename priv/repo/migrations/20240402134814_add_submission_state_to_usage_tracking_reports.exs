defmodule Lightning.Repo.Migrations.AddSubmissionStateToUsageTrackingReports do
  use Ecto.Migration

  def change do
    alter table(:usage_tracking_reports) do
      add :submission_status, :string, null: true
    end
  end
end
