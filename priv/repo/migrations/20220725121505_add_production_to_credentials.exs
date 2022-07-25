defmodule Lightning.Repo.Migrations.AddProductionToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add :production, :boolean, default: false
    end
  end
end
