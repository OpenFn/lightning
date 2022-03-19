defmodule Lightning.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :log, {:array, :string}
      add :exit_code, :integer
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      add :event_id, references(:invocation_events, on_delete: :nothing, type: :binary_id),
        null: false

      timestamps()
    end

    create index(:runs, [:event_id])
  end
end
