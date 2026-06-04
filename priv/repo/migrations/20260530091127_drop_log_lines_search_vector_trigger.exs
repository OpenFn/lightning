defmodule Lightning.Repo.Migrations.DropLogLinesSearchVectorTrigger do
  use Ecto.Migration

  def up do
    execute("SET lock_timeout = '5s'")
    execute("DROP TRIGGER IF EXISTS set_search_vector ON log_lines")
    execute("DROP FUNCTION IF EXISTS update_search_vector()")
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION public.update_search_vector()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
      begin
        UPDATE log_lines SET search_vector = to_tsvector('english_nostop', message) WHERE id = NEW.id;
        RETURN NEW;
      end
    $function$ ;
    """)

    execute("""
    CREATE TRIGGER set_search_vector
    AFTER INSERT ON log_lines FOR EACH ROW
    WHEN (NEW."search_vector" IS NULL)
    EXECUTE PROCEDURE update_search_vector();
    """)
  end
end
