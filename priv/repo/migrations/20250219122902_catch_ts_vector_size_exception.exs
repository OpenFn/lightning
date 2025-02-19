defmodule Lightning.Repo.Migrations.CatchTsVectorSizeException do
  use Ecto.Migration

  def up do
    execute "DROP TRIGGER IF EXISTS set_search_vector ON dataclips"

    execute "DROP FUNCTION IF EXISTS update_dataclip_search_vector"

    execute("""
    CREATE OR REPLACE FUNCTION update_dataclip_search_vector()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
    BEGIN
      BEGIN
        UPDATE dataclips
        SET search_vector = jsonb_to_tsvector('english_nostop', body, '"all"')
        WHERE id = NEW.id;
      EXCEPTION
        WHEN program_limit_exceeded THEN
          RAISE NOTICE 'Message too long for tsvector at id: %. Error: %', NEW.id, SQLERRM;
      END;

      RETURN NEW;
    END;
    $function$;
    """)

    execute("""
    CREATE TRIGGER set_search_vector
    AFTER INSERT ON dataclips FOR EACH ROW
    WHEN (NEW."search_vector" IS NULL)
    EXECUTE PROCEDURE update_dataclip_search_vector()
    """)
  end

  def down do
    execute "DROP TRIGGER IF EXISTS set_search_vector ON dataclips"

    execute "DROP FUNCTION IF EXISTS update_dataclip_search_vector"

    execute("""
    CREATE OR REPLACE FUNCTION update_dataclip_search_vector()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
      begin
        UPDATE dataclips SET search_vector = jsonb_to_tsvector('english_nostop', body, '"all"') WHERE id = NEW.id;
        RETURN NEW;
      end
    $function$ ;
    """)

    execute("""
    CREATE TRIGGER set_search_vector
    AFTER INSERT ON dataclips FOR EACH ROW
    WHEN (NEW."search_vector" IS NULL)
    EXECUTE PROCEDURE update_dataclip_search_vector()
    """)
  end
end
