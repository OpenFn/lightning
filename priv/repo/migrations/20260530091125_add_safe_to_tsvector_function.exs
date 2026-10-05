defmodule Lightning.Repo.Migrations.AddSafeToTsvectorFunction do
  use Ecto.Migration

  def up do
    # Deliberately not STRICT: a STRICT function returns NULL for a NULL doc,
    # which would leave search_vector NULL forever and stuck in the pending
    # index. COALESCE instead so the result is always a non-NULL tsvector.
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
