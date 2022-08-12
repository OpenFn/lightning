defmodule Lightning.Repo.Migrations.AddSchemaToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add :schema, :string, default: "raw", size: 40, null: false
    end
  end
end
