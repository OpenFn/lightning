defmodule Lightning.Repo.Migrations.CreateAdaptorCacheEntries do
  use Ecto.Migration

  def change do
    create table(:adaptor_cache_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :key, :string, null: false
      add :data, :binary, null: false
      add :content_type, :string, default: "application/json"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:adaptor_cache_entries, [:kind, :key])
    create index(:adaptor_cache_entries, [:kind])
  end
end
