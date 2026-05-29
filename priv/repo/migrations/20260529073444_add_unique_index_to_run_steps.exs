defmodule Lightning.Repo.Migrations.AddUniqueIndexToRunSteps do
  use Ecto.Migration

  def up do
    # Dedupe existing (run_id, step_id) rows, keeping the earliest by id, so the
    # unique index can build.
    execute("""
    DELETE FROM run_steps a
    USING run_steps b
    WHERE a.run_id = b.run_id
      AND a.step_id = b.step_id
      AND a.id > b.id
    """)

    # The non-unique index from 20240826070130 shares the default name with the
    # unique index below, so drop it first before creating the unique one.
    drop_if_exists index(:run_steps, [:run_id, :step_id])

    create unique_index(:run_steps, [:run_id, :step_id])
  end

  def down do
    drop_if_exists unique_index(:run_steps, [:run_id, :step_id])

    create index(:run_steps, [:run_id, :step_id])
  end
end
