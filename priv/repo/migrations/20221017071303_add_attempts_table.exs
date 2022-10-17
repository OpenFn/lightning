defmodule Lightning.Repo.Migrations.AddAttemptsTable do
  use Ecto.Migration

  def change do
    create table(:attempt_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason_id, references(:invocation_reasons, on_delete: :nothing, type: :binary_id), null: false

      timestamps()
    end
  end
end
