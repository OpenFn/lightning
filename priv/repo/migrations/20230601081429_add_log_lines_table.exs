defmodule Lightning.Repo.Migrations.AddLogLinesTable do
  use Ecto.Migration

  def change do
    create table(:log_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :string
      add :timestamp, :integer
      add :run_id, references(:runs, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(updated_at: false)
    end

    create index(:log_lines, [:run_id])
  end
end
