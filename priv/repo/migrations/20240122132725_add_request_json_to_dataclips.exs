defmodule Lightning.Repo.Migrations.AddRequestJsonToDataclips do
  use Ecto.Migration

  def change do
    alter table(:dataclips) do
      add :request, :map
    end
  end
end
