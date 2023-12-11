defmodule Lightning.Repo.Migrations.RemoveRunFkOnLogLines do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE log_lines
    DROP CONSTRAINT log_lines_run_id_fkey
    """)
  end

  def down do
    execute("""
    ALTER TABLE log_lines
    ADD CONSTRAINT log_lines_run_id_fkey
    FOREIGN KEY (run_id)
    REFERENCES runs(id) ON DELETE CASCADE
    """)
  end
end
