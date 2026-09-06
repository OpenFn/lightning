defmodule Lightning.Repo.Migrations.AddPartialIndexForDataclipWipe do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Retention's per-project wipe query filters on project_id + inserted_at
    # and excludes already-wiped/named rows. Without this, only the plain
    # project_id index applies and the rest falls to a row-by-row filter, so
    # each pass re-walks every already-wiped row for that project. It is
    # narrower than the plain project_id index because wiped and named rows
    # drop out, but projects with no dataclip_retention_period never wipe, so
    # it still carries every un-wiped unnamed dataclip they have.
    # A failed CREATE INDEX CONCURRENTLY leaves an INVALID index that IF NOT
    # EXISTS would skip on retry, silently leaving the dead index in place.
    # Drop any invalid leftover first so a re-run rebuilds cleanly.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_index i ON i.indexrelid = c.oid
        WHERE c.relname = 'dataclips_pending_wipe_idx'
          AND NOT i.indisvalid
      ) THEN
        EXECUTE 'DROP INDEX dataclips_pending_wipe_idx';
      END IF;
    END $$;
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS dataclips_pending_wipe_idx
    ON dataclips (project_id, inserted_at)
    WHERE wiped_at IS NULL AND name IS NULL
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS dataclips_pending_wipe_idx")
  end
end
