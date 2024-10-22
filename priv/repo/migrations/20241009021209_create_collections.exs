defmodule Lightning.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  def change do
    create table(:collections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string

      add :project_id,
          references(:projects, on_delete: :delete_all, type: :binary_id, null: false)

      timestamps()
    end

    create unique_index(:collections, [:name])

    create table(:collections_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string
      add :value, :string

      add :collection_id,
          references(:collections, type: :binary_id, on_delete: :delete_all, null: false)

      timestamps(type: :naive_datetime_usec)
    end

    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm",
            "DROP EXTENSION IF EXISTS pg_trgm"

    create unique_index(:collections_items, [:collection_id, :key])

    execute "CREATE INDEX collections_items_key_trgm_idx ON collections_items USING GIN (key gin_trgm_ops)",
            "DROP INDEX IF EXISTS collections_items_key_trgm_idx"
  end
end
