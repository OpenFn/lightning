defmodule Lightning.Repo.Migrations.ScopeCollectionNameUniquenessToProject do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:collections, [:name])
    create unique_index(:collections, [:project_id, :name])
  end

  def down do
    dupes =
      repo().query!("SELECT name FROM collections GROUP BY name HAVING count(*) > 1")

    if dupes.num_rows > 0 do
      raise Ecto.MigrationError,
        message:
          "Cannot rollback: #{dupes.num_rows} collection name(s) exist in multiple projects. " <>
            "Remove duplicates before rolling back."
    end

    drop_if_exists unique_index(:collections, [:project_id, :name])
    create unique_index(:collections, [:name])
  end
end
