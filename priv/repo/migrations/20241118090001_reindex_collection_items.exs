defmodule Lightning.Repo.Migrations.ReindexCollectionItems do
  use Ecto.Migration
  @disable_migration_lock true
  @disable_ddl_transaction true

  def change do
    execute(
      """
      DROP INDEX collection_items_updated_at_index
      """,
      """
      CREATE INDEX collection_items_updated_at_index ON collection_items (updated_at)
      """
    )

    create index(:collection_items, [:collection_id, :inserted_at], concurrently: true)
    create index(:collection_items, [:collection_id, :updated_at], concurrently: true)
  end
end
