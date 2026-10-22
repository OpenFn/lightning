defmodule Lightning.Repo.Migrations.AddWorkspacePathToRepoConnections do
  use Ecto.Migration

  def change do
    alter table("project_repo_connections") do
      add :workspace_path, :string
    end
  end
end
