defmodule Lightning.Repo.Migrations.AddConfigPathToRepoConnections do
  use Ecto.Migration

  def change do
    alter table("project_repo_connections") do
      add :config_path, :string
    end

    execute("UPDATE project_repo_connections SET config_path='./config.json'")
  end
end
