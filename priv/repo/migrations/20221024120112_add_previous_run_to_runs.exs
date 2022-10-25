defmodule Lightning.Repo.Migrations.AddPreviousRunToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :previous_id, references(:runs, on_delete: :delete_all, type: :binary_id), null: true
    end

    create index(:runs, [:previous_id])
  end
end
