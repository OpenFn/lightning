defmodule Lightning.Repo.Migrations.AddProjectFiles do
  use Ecto.Migration

  def change do
    create table(:project_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :file, :string
      add :size, :integer
      add :type, :string, null: false
      add :status, :string, null: false
      add :created_by_id, references(:users, type: :binary_id), null: false
      add :project_id, references(:projects, type: :binary_id), null: false

      timestamps()
    end
  end
end
