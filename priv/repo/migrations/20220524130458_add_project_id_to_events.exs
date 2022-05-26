defmodule Lightning.Repo.Migrations.AddProjectIdToEvents do
  use Ecto.Migration

  def change do
    alter table(:invocation_events) do
      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:invocation_events, [:project_id])
  end
end
