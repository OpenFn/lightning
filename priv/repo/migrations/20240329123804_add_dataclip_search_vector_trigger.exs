defmodule Lightning.Repo.Migrations.AddDataclipSearchVectorTrigger do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE OR REPLACE FUNCTION public.update_dataclip_search_vector()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
        begin
          UPDATE dataclips SET search_vector = jsonb_to_tsvector('english_nostop', body, '"all"') WHERE id = NEW.id;
          RETURN NEW;
        end
      $function$ ;
      """,
      "DROP FUNCTION IF EXISTS update_dataclip_search_vector;"
    )

    table = "dataclips"

    execute(
      """
      CREATE TRIGGER set_search_vector
      AFTER INSERT ON #{table} FOR EACH ROW
      WHEN (NEW."search_vector" IS NULL)
      EXECUTE PROCEDURE update_dataclip_search_vector();
      """,
      """
      DROP TRIGGER IF EXISTS set_search_vector ON #{table};
      """
    )
  end
end
