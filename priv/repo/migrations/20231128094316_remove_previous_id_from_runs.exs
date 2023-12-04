defmodule Lightning.Repo.Migrations.RemovePreviousIdFromRuns do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE runs
    DROP COLUMN previous_id
    """)
  end

  def down do
    execute("""
    ALTER TABLE runs
    ADD COLUMN previous_id uuid
    """)

    execute("""
    ALTER TABLE runs
    ADD CONSTRAINT runs_previous_id_fkey
    FOREIGN KEY (previous_id)
    REFERENCES runs(id) ON DELETE CASCADE
    """)
  end
end
