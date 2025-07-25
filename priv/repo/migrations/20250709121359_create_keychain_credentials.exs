defmodule Lightning.Repo.Migrations.CreateKeychainCredentials do
  use Ecto.Migration

  def change do
    create table(:keychain_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :path, :string, null: false
      add :created_by_id, references(:users, on_delete: :restrict, type: :binary_id), null: false

      add :default_credential_id,
          references(:credentials, on_delete: :nilify_all, type: :binary_id),
          null: true

      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps()
    end

    create unique_index(:keychain_credentials, [:name, :project_id])
    create index(:keychain_credentials, [:project_id])
  end
end
