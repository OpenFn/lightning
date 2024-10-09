defmodule Lightning.Repo.Migrations.CreateCollectionsEntries do
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
          references(:collections, on_delete: :delete_all, type: :binary_id, null: false)

      timestamps()
    end

    create unique_index(:collections_items, [:collection_id, :key])
  end
end
