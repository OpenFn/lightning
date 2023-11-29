defmodule Lightning.Repo.Migrations.RemoveAttemptRunsAttemptsFk do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE attempt_runs
    DROP CONSTRAINT attempt_runs_attempt_id_fkey
    """)
  end

  def down do
    execute("""
      ALTER TABLE attempt_runs
      ADD CONSTRAINT attempt_runs_attempt_id_fkey
      FOREIGN KEY (attempt_id)
      REFERENCES attempts(id) ON DELETE CASCADE
    """)
  end
end
