defmodule Lightning.Repo.Migrations.AddSafeToTsvectorFunction do
  use Ecto.Migration

  def up do
    # Not STRICT: a STRICT function returns NULL (without running) when `doc` is
    # NULL, which would leave the row's search_vector NULL forever and stuck in
    # the pending index. COALESCE the doc instead so the function always yields
    # a non-NULL tsvector. CREATE OR REPLACE keeps the migration re-runnable.
    execute("""
    CREATE OR REPLACE FUNCTION safe_to_tsvector(config regconfig, doc text) RETURNS tsvector
    LANGUAGE plpgsql IMMUTABLE AS $$
    BEGIN
      RETURN to_tsvector(config, COALESCE(doc, ''));
    EXCEPTION WHEN program_limit_exceeded THEN
      RETURN ''::tsvector;
    END;
    $$;
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS safe_to_tsvector(regconfig, text);")
  end
end
