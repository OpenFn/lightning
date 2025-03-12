defmodule Lightning.Repo.Migrations.CreateOauthTokensTable do
  use Ecto.Migration

  def change do
    create table(:oauth_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :binary, null: false
      add :scopes, {:array, :string}, null: false
      add :oauth_client_id, references(:oauth_clients, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:oauth_tokens, [:oauth_client_id])
    create index(:oauth_tokens, [:user_id])
    create unique_index(:oauth_tokens, [:user_id, :oauth_client_id, :scopes])

    alter table(:credentials) do
      add :oauth_token_id, references(:oauth_tokens, type: :binary_id)
    end

    create index(:credentials, [:oauth_token_id])
  end
end
