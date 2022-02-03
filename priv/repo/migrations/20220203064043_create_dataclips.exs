defmodule Lightning.Repo.Migrations.CreateDataclips do
  use Ecto.Migration

  def change do
    create table(:dataclips, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :map
      add :type, :string

      timestamps()
    end
  end
end
