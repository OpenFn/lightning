defmodule Lightning.Repo.Migrations.CollectionItemsSequence do
  use Ecto.Migration
  @disable_migration_lock true
  @disable_ddl_transaction true

  def up do
    execute("CREATE SEQUENCE collection_items_id_seq")

    alter table(:collection_items) do
      modify :id, :bigint,
        null: false,
        default: fragment("nextval('collection_items_id_seq'::regclass)")
    end

    execute("SELECT setval('collection_items_id_seq'::regclass, MAX(id)) FROM collection_items")
  end

  def down do
    alter table(:collection_items) do
      modify :id, :bigint, null: true, default: nil
    end

    execute("DROP SEQUENCE collection_items_id_seq")
  end
end
