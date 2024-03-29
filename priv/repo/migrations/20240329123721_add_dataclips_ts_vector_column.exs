defmodule Lightning.Repo.Migrations.AddDataclipsTsVectorColumn do
  use Ecto.Migration

  def change do
    alter table(:dataclips) do
      add :search_vector, :tsvector, null: true
    end
  end
end
