defmodule Lightning.Repo.Migrations.IncreaseCollectionsItems do
  use Ecto.Migration

  def change do
    alter table(:collections_items, primary_key: false) do
      modify :value, :string, length: 1_000_000
    end
  end
end
