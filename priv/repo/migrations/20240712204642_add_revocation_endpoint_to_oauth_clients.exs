defmodule Lightning.Repo.Migrations.AddRevokeEndpointToOauthClients do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      add :revocation_endpoint, :string
    end
  end
end
