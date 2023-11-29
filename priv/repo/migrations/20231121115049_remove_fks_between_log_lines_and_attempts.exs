defmodule Lightning.Repo.Migrations.RemoveFksBetweenLogLinesAndAttempts do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE log_lines
    DROP CONSTRAINT log_lines_attempt_id_fkey
    """)
  end

  def down do
    execute("""
    ALTER TABLE log_lines
    ADD CONSTRAINT log_lines_attempt_id_fkey
    FOREIGN KEY (attempt_id)
    REFERENCES attempts(id)
    ON DELETE CASCADE
    """)
  end
end
