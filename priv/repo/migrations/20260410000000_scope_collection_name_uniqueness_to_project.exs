defmodule Lightning.Repo.Migrations.ScopeCollectionNameUniquenessToProject do
  use Ecto.Migration

  def change do
    drop unique_index(:collections, [:name])
    create unique_index(:collections, [:project_id, :name])
  end
end
