defmodule Lightning.Repo.Migrations.AddLogLinesPendingSearchIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @num_partitions 100

  def up do
    # Create the partial index on the parent table (ONLY), unattached so far.
    execute("""
    CREATE INDEX IF NOT EXISTS log_lines_pending_search_idx
    ON ONLY log_lines (timestamp)
    WHERE search_vector IS NULL
    """)

    # Build each partition's index CONCURRENTLY (cannot be done on the
    # partitioned parent in PG15), then attach them to the parent index.
    manage_partitions(@num_partitions, &create_partition_index/2)
    manage_partitions(@num_partitions, &attach_partition_index/2)
  end

  def down do
    # Dropping the parent index cascades to the attached partition indexes.
    execute("DROP INDEX IF EXISTS log_lines_pending_search_idx")
  end

  defp manage_partitions(num_partitions, manage_function) do
    1..num_partitions
    |> Enum.each(&manage_function.(num_partitions, &1))
  end

  defp create_partition_index(_num_partitions, part_num) do
    # A failed CREATE INDEX CONCURRENTLY leaves an INVALID index behind. The
    # IF NOT EXISTS below would then skip rebuilding it, and the subsequent
    # ATTACH would leave the parent permanently INVALID. Drop any invalid
    # leftover first so a re-run rebuilds it cleanly. (A valid index is kept;
    # only invalid ones are dropped.)
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_index i ON i.indexrelid = c.oid
        WHERE c.relname = 'log_lines_#{part_num}_pending_search_idx'
          AND NOT i.indisvalid
      ) THEN
        EXECUTE 'DROP INDEX log_lines_#{part_num}_pending_search_idx';
      END IF;
    END $$;
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS log_lines_#{part_num}_pending_search_idx
    ON log_lines_#{part_num} (timestamp)
    WHERE search_vector IS NULL
    """)
  end

  defp attach_partition_index(_num_partitions, part_num) do
    execute("""
    ALTER INDEX log_lines_pending_search_idx
    ATTACH PARTITION log_lines_#{part_num}_pending_search_idx
    """)
  end
end
