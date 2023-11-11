defmodule Lightning.Repo.Migrations.AddAttemptIdToLogLine do
  use Ecto.Migration

  def change do
    alter table(:log_lines) do
      add :attempt_id, references(:attempts, type: :binary_id, on_delete: :delete_all), null: true
      remove :timestamp, :integer
      add :level, :string, null: true
      add :source, :string, length: 8, null: true
    end

    rename table(:log_lines), :body, to: :message
    rename table(:log_lines), :inserted_at, to: :timestamp

    execute """
            UPDATE log_lines
            SET attempt_id = (
              SELECT attempt_id from runs
              JOIN attempt_runs ar ON ar.run_id = runs.id
              JOIN attempts a ON a.id = ar.attempt_id
              WHERE runs.inserted_at >= a.inserted_at
              AND runs.id = log_lines.run_id
            )
            """,
            ""

    execute """
            ALTER TABLE log_lines ALTER COLUMN attempt_id DROP NOT NULL;
            """,
            ""

    execute """
            ALTER TABLE log_lines ALTER COLUMN run_id DROP NOT NULL;
            """,
            """
            ALTER TABLE log_lines ALTER COLUMN run_id SET NOT NULL;
            """

    create index(:log_lines, [:attempt_id])
  end
end
