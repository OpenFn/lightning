defmodule Lightning.Repo.Migrations.CreateCredentials do
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :body, :map, default: %{}

      timestamps()
    end
  end
end
