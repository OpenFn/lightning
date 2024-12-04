defmodule Lightning.Repo.Migrations.SetCollectionItemsSerialId do
  use Ecto.Migration

  def up do
    execute """
    WITH ordered_rows AS (
      SELECT collection_id, key, row_number() OVER () AS rn
      FROM collection_items
      ORDER BY inserted_at ASC
    )
    UPDATE collection_items
    SET id = ordered_rows.rn
    FROM ordered_rows
    WHERE collection_items.collection_id = ordered_rows.collection_id
      AND collection_items.key = ordered_rows.key;
    """
  end

  def down do
    :ok
  end
end
