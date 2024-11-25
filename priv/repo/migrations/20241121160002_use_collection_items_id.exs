defmodule Lightning.Repo.Migrations.UseCollectionItemsSerialId do
  use Ecto.Migration

  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Collections.Item

  def up do
    items =
      Repo.all(from(i in Item, order_by: [asc: i.inserted_at]))
      |> Enum.with_index(fn item, index ->
        item
        |> Map.take([:collection_id, :key, :value, :inserted_at, :updated_at])
        |> Map.put(:id, index + 1)
      end)

    items
    |> Enum.chunk_every(10_000)
    |> Enum.each(
      &Repo.insert_all(Item, &1,
        conflict_target: [:collection_id, :key],
        on_conflict: {:replace, [:id]}
      )
    )
  end

  def down do
    :ok
  end
end
