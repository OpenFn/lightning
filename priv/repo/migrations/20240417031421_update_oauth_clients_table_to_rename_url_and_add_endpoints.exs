defmodule Lightning.Repo.Migrations.UpdateOauthClientsTableToRenameUrlAndAddEndpoints do
  use Ecto.Migration

  def change do
    # Rename the base_url to authorization_endpoint
    rename table(:oauth_clients), :base_url, to: :authorization_endpoint

    # Add new columns token_endpoint and userinfo_endpoint
    alter table(:oauth_clients) do
      add :token_endpoint, :string
      add :userinfo_endpoint, :string
    end
  end
end
