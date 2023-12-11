defmodule Lightning.Repo.Migrations.RemoveRunFkOnLogLinesMonolith do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE log_lines_monolith
    DROP CONSTRAINT log_lines_monolith_run_id_fkey
    """)
  end

  def down do
    execute("""
    ALTER TABLE log_lines_monolith
    ADD CONSTRAINT "log_lines_monolith_run_id_fkey"
    FOREIGN KEY (run_id)
    REFERENCES runs(id) ON DELETE CASCADE
    """)
  end
end
