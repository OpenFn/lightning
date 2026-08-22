defmodule Lightning.Repo.Migrations.AddDataclipsPendingSearchIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Partial index that keeps "find pending rows" cheap for the background
    # indexing worker. dataclips is an unpartitioned table, so this is a single
    # CONCURRENTLY-built index (no per-partition build-and-attach dance). The
    # index stays small because existing rows already have a non-NULL
    # search_vector, so only freshly-inserted, not-yet-indexed rows match.
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS dataclips_pending_search_idx
    ON dataclips (inserted_at)
    WHERE search_vector IS NULL
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS dataclips_pending_search_idx")
  end
end
