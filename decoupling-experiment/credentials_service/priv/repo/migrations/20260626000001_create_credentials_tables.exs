defmodule CredentialsService.Repo.Migrations.CreateCredentialsTables do
  use Ecto.Migration

  def change do
    create table(:oauth_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :client_id, :string
      # NOTE: plaintext at rest in Lightning today (see OauthClient moduledoc).
      add :client_secret, :string
      add :authorization_endpoint, :string
      add :token_endpoint, :string
      add :revocation_endpoint, :string
      add :user_id, :binary_id

      timestamps()
    end

    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :external_id, :string
      add :schema, :string
      add :scheduled_deletion, :utc_datetime
      add :transfer_status, :string
      add :user_id, :binary_id, null: false

      add :oauth_client_id,
          references(:oauth_clients, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:credentials, [:name, :user_id])
    create index(:credentials, [:user_id])

    create table(:credential_bodies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false, default: "main"
      # Cloak ciphertext (encrypted JSON map).
      add :body, :binary

      add :credential_id,
          references(:credentials, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create unique_index(:credential_bodies, [:credential_id, :name])

    create table(:project_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, :binary_id, null: false

      add :credential_id,
          references(:credentials, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create unique_index(:project_credentials, [:project_id, :credential_id])
  end
end
