defmodule Lightning.Repo.Migrations.RemoveRunFkOnAttemptRuns do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE attempt_runs
    DROP CONSTRAINT attempt_runs_run_id_fkey
    """)
  end

  def down do
    execute("""
      ALTER TABLE attempt_runs
      ADD CONSTRAINT attempt_runs_run_id_fkey
      FOREIGN KEY (run_id)
      REFERENCES runs(id) ON DELETE CASCADE
    """)
  end
end
