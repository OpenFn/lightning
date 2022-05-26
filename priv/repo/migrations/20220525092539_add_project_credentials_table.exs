defmodule Lightning.Repo.Migrations.AddProjectCredentialsTable do
  use Ecto.Migration

  def change do
    create table(:project_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id)
      add :credential_id, references(:credentials, type: :binary_id)

      timestamps()
    end

    alter table(:jobs) do
      add :project_credential_id,
          references(:project_credentials, type: :binary_id, on_delete: :nilify_all),
          null: true

      remove :credential_id, references(:credentials, type: :binary_id)
    end

    create index(:project_credentials, [:credential_id])
    create index(:project_credentials, [:project_id])
    create unique_index(:project_credentials, [:project_id, :credential_id])
  end
end
