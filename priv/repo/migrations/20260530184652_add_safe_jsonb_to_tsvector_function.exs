defmodule Lightning.Repo.Migrations.AddSafeJsonbToTsvectorFunction do
  use Ecto.Migration

  def up do
    # Deliberately not STRICT: a STRICT function returns NULL for a NULL doc,
    # which would leave search_vector NULL forever and stuck in the pending
    # index (e.g. a wiped dataclip with a NULL body). COALESCE instead so the
    # result is always a non-NULL tsvector.
    execute("""
    CREATE OR REPLACE FUNCTION safe_jsonb_to_tsvector(config regconfig, doc jsonb)
    RETURNS tsvector LANGUAGE plpgsql IMMUTABLE AS $$
    BEGIN
      RETURN jsonb_to_tsvector(config, COALESCE(doc, '{}'::jsonb), '"all"');
    EXCEPTION WHEN program_limit_exceeded THEN
      RETURN ''::tsvector;
    END;
    $$;
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS safe_jsonb_to_tsvector(regconfig, jsonb);")
  end
end
