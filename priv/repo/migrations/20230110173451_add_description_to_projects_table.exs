defmodule Lightning.Repo.Migrations.AddDescriptionToProjectsTable do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :description, :string, null: true
    end
  end
end
