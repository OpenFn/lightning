defmodule Lightning.Repo.Migrations.AddRoleToProjectUsers do
  use Ecto.Migration

  def change do
    alter table(:project_users) do
      add :role, :string, default: "editor", null: false
    end
  end
end
