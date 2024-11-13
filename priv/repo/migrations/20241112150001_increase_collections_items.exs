defmodule Lightning.Repo.Migrations.IncreaseCollectionsItems do
  use Ecto.Migration

  def change do
    alter table(:collections_items, primary_key: false) do
      modify :value, :string, size: 1_000_000, from: {:string, size: 255}
    end
  end
end
