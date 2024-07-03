defmodule Lightning.Repo.Migrations.AddGithubTokenToUsers do
  use Ecto.Migration

  def change do
    alter table("users") do
      add :github_oauth_token, :binary
    end
  end
end
