defmodule Lightning.Repo.Migrations.AddProjectIdToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:jobs, [:project_id])
  end
end
