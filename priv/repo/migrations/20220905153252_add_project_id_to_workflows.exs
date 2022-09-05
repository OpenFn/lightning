defmodule Lightning.Repo.Migrations.AddProjectIdToWorkflows do
  use Ecto.Migration

  def change do
    alter table(:workflows) do
      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create unique_index(:workflows, [:name, :project_id])
  end
end
