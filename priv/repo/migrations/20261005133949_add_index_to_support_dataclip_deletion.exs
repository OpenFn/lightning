defmodule Lightning.Repo.Migrations.AddIndexToSupportDataclipDeletion do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # History retention's per-project dataclip delete (the CTE body in
    # Lightning.Projects.delete_history_for/1, and the Repo.aggregate count
    # that precedes it in delete_dataclips/2) filters on project_id +
    # inserted_at and excludes named rows. Neither statement could use
    # dataclips_pending_wipe_idx - that index is predicated on
    # `wiped_at IS NULL`, which the delete query doesn't constrain, and in
    # steady state the rows it wants are precisely the already-wiped ones
    # (dataclip_retention_period is validated <= history_retention_period, so
    # the delete window sits inside the wiped range). The planner fell back to
    # a parallel seq scan of the whole table instead.
    #
    # `wiped_at` is deliberately NOT a key column here: the delete query has no
    # predicate on it, so it would only widen the entries. That does mean this
    # index does NOT supersede dataclips_pending_wipe_idx despite having the
    # same key columns and a looser predicate - with wiped_at absent from the
    # index, the wipe query's `wiped_at IS NULL` check falls back to the heap,
    # which is the per-row heap fetch that 20260904094625 was added to remove.
    # Keep both. Consolidating to one index would need a third index with
    # wiped_at as a trailing key column, not this one. Testing showed that a
    # single index serving both is a practical option, albeit with a small
    # performance penalty on the wipe query.
    #
    # A failed CREATE INDEX CONCURRENTLY leaves an INVALID index that
    # IF NOT EXISTS would skip on retry, silently leaving the dead index in
    # place. Drop any invalid leftover first so a re-run rebuilds cleanly.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_index i ON i.indexrelid = c.oid
        WHERE c.relname = 'dataclips_pending_delete_idx'
          AND NOT i.indisvalid
      ) THEN
        EXECUTE 'DROP INDEX dataclips_pending_delete_idx';
      END IF;
    END $$;
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS dataclips_pending_delete_idx
    ON dataclips (project_id, inserted_at)
    WHERE name IS NULL
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS dataclips_pending_delete_idx")
  end
end
