defmodule Lightning.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :body, :text
      add :enabled, :boolean, default: false, null: false

      timestamps()
    end
  end
end
