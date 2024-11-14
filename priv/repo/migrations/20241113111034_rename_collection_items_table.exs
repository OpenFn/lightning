defmodule Lightning.Repo.Migrations.RenameCollectionItemsTable do
  use Ecto.Migration

  def change do
    rename table(:collections_items), to: table(:collection_items)

    execute """
            ALTER INDEX collections_items_key_trgm_idx RENAME TO collection_items_key_trgm_idx
            """,
            """
            ALTER INDEX collection_items_key_trgm_idx RENAME TO collections_items_key_trgm_idx
            """

    execute """
            ALTER INDEX collections_items_collection_id_key_index RENAME TO collection_items_collection_id_key_index
            """,
            """
            ALTER INDEX collection_items_collection_id_key_index RENAME TO collections_items_collection_id_key_index
            """

    execute """
            ALTER INDEX collections_items_updated_at_index RENAME TO collection_items_updated_at_index
            """,
            """
            ALTER INDEX collection_items_updated_at_index RENAME TO collections_items_updated_at_index
            """

    execute """
            ALTER TABLE collection_items DROP CONSTRAINT collections_items_collection_id_fkey,
            ADD CONSTRAINT collection_items_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
            """,
            """
            ALTER TABLE collection_item DROP CONSTRAINT collection_items_collection_id_fkey,
            ADD CONSTRAINT collections_items_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
            """
  end
end
