defmodule Lightning.Repo.Migrations.AddScopesToOauthClients do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      add :mandatory_scopes, :string, null: true
      add :optional_scopes, :string, null: true
    end
  end
end
