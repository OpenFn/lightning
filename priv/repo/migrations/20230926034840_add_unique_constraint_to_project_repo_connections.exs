defmodule Lightning.Repo.Migrations.AddUniqueConstraintToProjectRepoConnections do
  use Ecto.Migration

  def change do
    create unique_index("project_repo_connections", [:project_id])
  end
end
