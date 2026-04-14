defmodule Lightning.Repo.Migrations.ScopeCollectionNameUniquenessToProject do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:collections, [:name])
    create unique_index(:collections, [:project_id, :name])
  end

  def down do
    raise "Cannot reverse: duplicate collection names may exist across projects"
  end
end
