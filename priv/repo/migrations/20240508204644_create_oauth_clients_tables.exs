defmodule Lightning.Repo.Migrations.CreateOauthClientsTables do
  use Ecto.Migration

  def change do
    # Create the oauth_clients table
    create table(:oauth_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :client_id, :string
      add :client_secret, :string
      add :authorization_endpoint, :string
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :token_endpoint, :string
      add :userinfo_endpoint, :string
      add :mandatory_scopes, :text, null: true
      add :optional_scopes, :text, null: true
      add :scopes_doc_url, :string, null: true
      add :global, :boolean, default: false

      timestamps()
    end

    # Create the project_oauth_clients table
    create table(:project_oauth_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id)
      add :oauth_client_id, references(:oauth_clients, type: :binary_id)

      timestamps()
    end

    # Create indexes for the project_oauth_clients table
    create index(:project_oauth_clients, [:oauth_client_id])
    create index(:project_oauth_clients, [:project_id])
    create unique_index(:project_oauth_clients, [:project_id, :oauth_client_id])

    # Alter the credentials table to add oauth_client_id
    alter table(:credentials) do
      add :oauth_client_id, references(:oauth_clients, on_delete: :nilify_all, type: :binary_id),
        null: true
    end
  end
end
