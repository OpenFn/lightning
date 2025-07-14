defmodule Lightning.Repo.Migrations.DropOauthTokensUniqueIndex do
  use Ecto.Migration

  def change do
    drop unique_index(:oauth_tokens, [:user_id, :oauth_client_id, :scopes])
  end
end
