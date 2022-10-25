defmodule Lightning.Repo.Migrations.RemoveEventFromRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      remove :event_id, references(:invocation_events, on_delete: :nothing, type: :binary_id),
        null: false
    end

    alter table(:dataclips) do
      remove :source_event_id,
             references(:invocation_events, on_delete: :delete_all, type: :binary_id),
             null: true
    end
  end
end
