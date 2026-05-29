defmodule Lightning.Repo.Migrations.AddUniqueIndexToLogLines do
  use Ecto.Migration

  # log_lines is HASH-partitioned by run_id, so its unique index must include
  # the partition key. (id, run_id) backs the ON CONFLICT used to make run:log
  # and run:batch_logs idempotent. Existing ids are UUIDs generated per-insert,
  # so no dedupe is needed before building the index.
  #
  # log_lines is one of the largest, hottest tables in prod, so we avoid the
  # ACCESS EXCLUSIVE lock a plain `create unique_index` would hold for the whole
  # build. You can't CREATE INDEX CONCURRENTLY on a partitioned parent in one
  # statement, so we: create an unattached (invalid) index on ONLY the parent,
  # build each partition's index CONCURRENTLY, then ATTACH them — the parent
  # flips to valid once every partition is attached. Requires running outside a
  # transaction (see 20240319125628_add_tsvector_index_to_log_lines).
  @disable_ddl_transaction true
  @disable_migration_lock true

  @num_partitions 100

  def up do
    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS log_lines_id_run_id_index
    ON ONLY log_lines (id, run_id)
    """)

    for part <- 0..(@num_partitions - 1) do
      child = "log_lines_#{part + 1}"
      child_index = "#{child}_id_run_id_index"

      execute("""
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS #{child_index}
      ON #{child} (id, run_id)
      """)

      execute("""
      ALTER INDEX log_lines_id_run_id_index
      ATTACH PARTITION #{child_index}
      """)
    end

    # The new unique btree leads with `id`, so it serves id-equality lookups too,
    # making the old hash(id) index redundant. Dropping it keeps the per-insert
    # index count net-neutral.
    execute("DROP INDEX IF EXISTS log_lines_id_index")
  end

  def down do
    execute("""
    CREATE INDEX IF NOT EXISTS log_lines_id_index
    ON ONLY log_lines USING hash (id)
    """)

    for part <- 0..(@num_partitions - 1) do
      child = "log_lines_#{part + 1}"
      child_index = "#{child}_id_index"

      execute("""
      CREATE INDEX CONCURRENTLY IF NOT EXISTS #{child_index}
      ON #{child} USING hash (id)
      """)

      execute("""
      ALTER INDEX log_lines_id_index
      ATTACH PARTITION #{child_index}
      """)
    end

    execute("DROP INDEX IF EXISTS log_lines_id_run_id_index")
  end
end
