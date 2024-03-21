defmodule Lightning.Repo.Migrations.RemoveUserIdFromProjectConnections do
  use Ecto.Migration

  def change do
    alter table("project_repo_connections") do
      remove :user_id, references("users")
    end
  end
end
