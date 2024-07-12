defmodule Lightning.Repo.Migrations.AddRevokeEndpointToOauthClients do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      add :revoke_endpoint, :string
    end
  end
end
