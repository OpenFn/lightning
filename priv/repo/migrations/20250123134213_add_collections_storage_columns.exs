defmodule Lightning.Repo.Migrations.AddCollectionsStorageColumns do
  use Ecto.Migration

  def change do
    alter table(:collections) do
      add :byte_size_sum, :integer, default: 0
    end

    alter table(:collection_items) do
      add :byte_size, :integer, default: 0
    end
  end
end
