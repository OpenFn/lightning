defmodule Lightning.Repo.Migrations.RefactorRunsForWorkorders do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :previous_id, references(:runs, on_delete: :delete_all, type: :binary_id), null: true

      remove :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false

      remove :event_id, references(:invocation_events, on_delete: :nothing, type: :binary_id),
        null: false
    end

    alter table(:dataclips) do
      remove :source_event_id,
             references(:invocation_events, on_delete: :delete_all, type: :binary_id),
             null: true
    end

    create index(:runs, [:previous_id])
  end
end
