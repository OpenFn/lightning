defmodule Lightning.Repo.Migrations.CreateTriggers do
  use Ecto.Migration

  def change do
    create table(:triggers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :comment, :string
      add :custom_path, :string
      add :job_id, references(:jobs, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create index(:triggers, [:job_id])
  end
end
