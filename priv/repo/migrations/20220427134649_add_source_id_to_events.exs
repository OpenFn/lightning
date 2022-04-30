defmodule Lightning.Repo.Migrations.AddSourceIdToEvents do
  use Ecto.Migration

  def change do
    alter table(:invocation_events) do
      add :source_id, references(:invocation_events, on_delete: :delete_all, type: :binary_id),
        null: true
    end

    create index(:invocation_events, [:source_id])
  end
end
