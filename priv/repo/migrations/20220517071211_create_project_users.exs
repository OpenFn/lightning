defmodule Lightning.Repo.Migrations.CreateProjectUsers do
  use Ecto.Migration

  def change do
    create table(:project_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)
      add :project_id, references(:projects, on_delete: :nothing, type: :binary_id)

      timestamps()
    end

    create index(:project_users, [:user_id])
    create index(:project_users, [:project_id])
    create unique_index(:project_users, [:project_id, :user_id])
  end
end
