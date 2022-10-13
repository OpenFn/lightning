defmodule Lightning.Repo.Migrations.RemoveProjectIdFromJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      remove :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false
    end
  end
end
