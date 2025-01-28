defmodule Lightning.Repo.Migrations.AddCollectionsStorageColumns do
  use Ecto.Migration

  def change do
    alter table(:collections) do
      add :byte_size_sum, :bigint, default: 0
    end
  end
end
