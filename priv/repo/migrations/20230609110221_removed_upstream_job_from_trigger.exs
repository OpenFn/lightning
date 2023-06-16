defmodule Lightning.Repo.Migrations.RemovedUpstreamJobFromTrigger do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      remove :upstream_job_id
    end
  end
end
