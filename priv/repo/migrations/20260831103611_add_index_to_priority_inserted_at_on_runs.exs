defmodule Lightning.Repo.Migrations.AddIndexToPriorityInsertedAtOnRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
      CREATE INDEX CONCURRENTLY runs_available_fifo_idx
      ON runs (priority, inserted_at) WHERE state = 'available';
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS runs_available_fifo_idx;")
  end
end
