defmodule Lightning.Repo.Migrations.AddDigestToProjectUsers do
  use Ecto.Migration

  def change do
    alter table(:project_users) do
      add :digest, :string, default: "weekly", null: false
    end
  end
end
