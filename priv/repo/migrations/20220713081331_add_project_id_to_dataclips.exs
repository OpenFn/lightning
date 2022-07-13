defmodule Lightning.Repo.Migrations.AddProjectIdToDataclips do
  use Ecto.Migration

  def change do
    alter table(:dataclips) do
      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:dataclips, [:project_id])
  end
end
