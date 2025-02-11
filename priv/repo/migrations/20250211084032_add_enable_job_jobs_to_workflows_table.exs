defmodule Lightning.Repo.Migrations.AddEnableJobJobsToWorkflowsTable do
  use Ecto.Migration

  def change do
    alter table("workflows") do
      add :enable_job_logs, :boolean, default: true
    end
  end
end
