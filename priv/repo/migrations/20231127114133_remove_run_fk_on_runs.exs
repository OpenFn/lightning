defmodule Lightning.Repo.Migrations.RemoveRunFkOnRuns do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE runs
    DROP CONSTRAINT runs_previous_id_fkey
    """)
  end

  def down do
    execute("""
    ALTER TABLE runs
    ADD CONSTRAINT runs_previous_id_fkey
    FOREIGN KEY (previous_id)
    REFERENCES runs(id) ON DELETE CASCADE
    """)
  end
end
