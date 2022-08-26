defmodule Lightning.Repo.Migrations.CreateAuthProviders do
  use Ecto.Migration

  def change do
    create table(:auth_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string

      add :client_id, :string
      add :client_secret, :string
      add :discovery_url, :string
      add :redirect_uri, :string

      timestamps()
    end
  end
end
