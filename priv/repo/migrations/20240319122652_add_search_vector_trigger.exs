defmodule Lightning.Repo.Migrations.AddSearchVectorTrigger do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE TEXT SEARCH DICTIONARY english_stem_nostop (
        Template = pg_catalog.simple
      );
      """,
      "DROP TEXT SEARCH CONFIGURATION english_nostop"
    )

    execute(
      """
      CREATE TEXT SEARCH CONFIGURATION public.english_nostop ( COPY = pg_catalog.english );
      """,
      "DROP TEXT SEARCH DICTIONARY english_stem_nostop"
    )

    execute(
      """
      ALTER TEXT SEARCH CONFIGURATION public.english_nostop
        ALTER MAPPING FOR asciiword, asciihword, hword_asciipart, hword, hword_part, word WITH english_stem_nostop;
      """,
      ""
    )

    execute(
      """
      CREATE OR REPLACE FUNCTION public.update_search_vector()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
        begin
          UPDATE log_lines SET search_vector = to_tsvector('english_nostop', message) WHERE id = NEW.id;
          RETURN NEW;
        end
      $function$ ;
      """,
      "DROP FUNCTION IF EXISTS update_search_vector;"
    )

    table = "log_lines"

    execute(
      """
      CREATE TRIGGER set_search_vector
      AFTER INSERT ON #{table} FOR EACH ROW
      WHEN (NEW."search_vector" IS NULL)
      EXECUTE PROCEDURE update_search_vector();
      """,
      """
      DROP TRIGGER IF EXISTS set_search_vector ON #{table};
      """
    )
  end
end
