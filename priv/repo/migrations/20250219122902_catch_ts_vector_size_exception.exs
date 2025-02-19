defmodule Lightning.Repo.Migrations.CatchTsVectorSizeException do
  use Ecto.Migration

  def change do
    execute(
      """
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
      """,
      """
      CREATE OR REPLACE FUNCTION update_dataclip_search_vector()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
        begin
          UPDATE dataclips SET search_vector = jsonb_to_tsvector('english_nostop', body, '"all"') WHERE id = NEW.id;
          RETURN NEW;
        end
      $function$ ;
      """
    )
  end
end
