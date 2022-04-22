defmodule Lightning.Repo.Migrations.AddUpstreamJobToTriggers do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :upstream_job_id, references(:jobs, on_delete: :delete_all, type: :binary_id),
        null: true

      add :type, :string, null: false
    end

    create index(:triggers, [:upstream_job_id])
  end
end
