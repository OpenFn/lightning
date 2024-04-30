defmodule Lightning.Repo.Migrations.AddOauthClientsTable do
  use Ecto.Migration

  def change do
    create table(:oauth_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :client_id, :string
      add :client_secret, :string
      add :base_url, :string
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end
  end
end
