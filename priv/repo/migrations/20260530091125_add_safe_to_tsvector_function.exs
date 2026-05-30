defmodule Lightning.Repo.Migrations.AddSafeToTsvectorFunction do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION safe_to_tsvector(config regconfig, doc text) RETURNS tsvector
    LANGUAGE plpgsql IMMUTABLE STRICT AS $$
    BEGIN
      RETURN to_tsvector(config, doc);
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
