defmodule Lightning.Repo.Migrations.AddTrigramIndexToDataclipNames do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Drop the old basic btree index on name (redundant with trigram index)
    drop_if_exists index("dataclips", [:name])

    # Create trigram GIN index for efficient ILIKE searches
    execute "CREATE INDEX dataclips_name_trgm ON dataclips USING GIN (name gin_trgm_ops) WHERE name IS NOT NULL",
            "DROP INDEX IF EXISTS dataclips_name_trgm"
  end

  def down do
    execute "DROP INDEX IF EXISTS dataclips_name_trgm"

    create index("dataclips", [:name])

    execute "DROP EXTENSION IF EXISTS pg_trgm"
  end
end
