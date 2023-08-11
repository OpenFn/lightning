defmodule Lightning.Repo.Migrations.CreateRepoProjectConnection do
  use Ecto.Migration

  def change do
    create table(:project_repos, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :github_installation_id, :string
      add :repo, :string
      add :branch, :string
      add :project_id, references(:projects, type: :binary_id)
      add :user_id, references(:users, type: :binary_id)

      timestamps()
    end
  end
end
