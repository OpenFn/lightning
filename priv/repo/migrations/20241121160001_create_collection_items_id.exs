defmodule Lightning.Repo.Migrations.CreateCollectionItemsSerialId do
  use Ecto.Migration

  def change do
    alter table(:collection_items) do
      add :id, :bigint
    end

    create unique_index(:collection_items, [:collection_id, :id])
  end
end
