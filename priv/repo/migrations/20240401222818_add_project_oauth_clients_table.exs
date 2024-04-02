defmodule Lightning.Repo.Migrations.AddProjectOauthClientsTable do
  use Ecto.Migration

  def change do
    create table(:project_oauth_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id)
      add :oauth_client_id, references(:oauth_clients, type: :binary_id)

      timestamps()
    end

    create index(:project_oauth_clients, [:oauth_client_id])
    create index(:project_oauth_clients, [:project_id])
    create unique_index(:project_oauth_clients, [:project_id, :oauth_client_id])
  end
end
