defmodule Lightning.Repo.Migrations.AddProjectCredentialsTable do
  use Ecto.Migration

  def change do
    create table(:project_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id)
      add :credential_id, references(:credentials, type: :binary_id)

      timestamps()
    end

    create index(:project_credentials, [:project_id, :credential_id])
  end
end
