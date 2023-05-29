defmodule Lightning.Repo.Migrations.AddRunLogsTable do
  use Ecto.Migration

  def change do
    create table(:run_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :string
      add :timestamp, :integer
      add :run_id, references(:runs, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create unique_index(:run_logs, [:run_id])
  end
end
