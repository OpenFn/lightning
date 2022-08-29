defmodule Lightning.Repo.Migrations.AddWorkflowIdToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :workflow_id, references(:workflows, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:jobs, [:workflow_id])
  end
end
