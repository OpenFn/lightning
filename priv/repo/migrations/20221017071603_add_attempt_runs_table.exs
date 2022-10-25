defmodule Lightning.Repo.Migrations.AddAttemptRunsTable do
  use Ecto.Migration

  def change do
    create table(:attempt_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :attempt_id, references(:attempts, on_delete: :delete_all, type: :binary_id),
        primary_key: true

      add :run_id, references(:runs, on_delete: :delete_all, type: :binary_id), primary_key: true

      timestamps()
    end
  end
end
