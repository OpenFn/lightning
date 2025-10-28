defmodule Lightning.Repo.Migrations.AddProductionTagToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add :production_tag, :string
    end
  end
end
