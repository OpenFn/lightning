defmodule Lightning.Repo.Migrations.AddTsvectorIndexToDataclips do
  use Ecto.Migration

  def change do
    create index(:dataclips, [:search_vector], using: :gin)
  end
end
