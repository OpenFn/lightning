defmodule Lightning.Repo.Migrations.RemoveUserIdFromProjectConnections do
  use Ecto.Migration

  def change do
    alter table("project_repo_connections") do
      remove :user_id, references("users", type: :binary_id)
      add :access_token, :binary
    end
  end
end
