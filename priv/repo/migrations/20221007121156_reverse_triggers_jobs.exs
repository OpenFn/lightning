defmodule Lightning.Repo.Migrations.ReverseTriggersJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :trigger_id, references(:triggers, on_delete: :delete_all, type: :uuid),
        null: true
    end
    alter table(:triggers) do
      remove :job_id, :uuid
      add :workflow_id, references(:workflows, on_delete: :delete_all, type: :uuid),
        null: true
    end
  end
end
