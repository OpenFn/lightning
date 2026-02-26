defmodule Lightning.Repo.Migrations.AddAuthMethodToOauthClients do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      add :auth_method, :string, default: "client_secret_post", null: false
      add :private_key, :binary
    end
  end
end
