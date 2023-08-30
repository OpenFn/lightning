defmodule Lightning.Repo.Migrations.CreateProjectRepoConnections do
  use Ecto.Migration

  def change do
    create table(:project_repo_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :github_installation_id, :string
      add :repo, :string
      add :branch, :string
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end
  end
end
