# NBNB For WIP branch only - this is just a shim branch until
# the branch that removes attempts FKs is merged in.
defmodule Lightning.Repo.Migrations.ShimMigrationNotForMerging do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE attempt_runs
    DROP CONSTRAINT attempt_runs_attempt_id_fkey
    """)
    execute("""
    ALTER TABLE log_lines
    DROP CONSTRAINT log_lines_attempt_id_fkey
    """)
  end

  def change do
    execute("""
    ALTER TABLE attempt_runs
    ADD CONSTRAINT attempt_runs_attempt_id_fkey
    FOREIGN KEY (attempt_id)
    REFERENCES attempts(id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE log_lines
    ADD CONSTRAINT log_lines_attempt_id_fkey
    FOREIGN KEY (attempt_id)
    REFERENCES attempts(id)
    ON DELETE CASCADE
    """)
  end
end
