defmodule Lightning.Repo.Migrations.AddOauthClientIdToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add :oauth_client_id, references(:oauth_clients, on_delete: :delete_all, type: :binary_id),
        null: true
    end
  end
end
