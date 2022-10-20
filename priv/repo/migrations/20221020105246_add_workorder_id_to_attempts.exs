defmodule Lightning.Repo.Migrations.AddWorkorderIdToAttempts do
  use Ecto.Migration

  def change do
    alter table(:attempts) do
      add :workorder_id, references(:workorders, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:attempts, [:workorder_id])
  end
end
