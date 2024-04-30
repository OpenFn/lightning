defmodule Lightning.Repo.Migrations.AddGlobalToOauthClients do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      add :global, :boolean, default: false
    end
  end
end
