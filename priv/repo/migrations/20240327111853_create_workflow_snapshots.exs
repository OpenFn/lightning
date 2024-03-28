defmodule Lightning.Repo.Migrations.CreateWorkflowSnapshots do
  use Ecto.Migration

  def change do
    create table(:workflow_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workflow_id,
          references(:workflows, on_delete: :delete_all, type: :binary_id, null: false)

      add :name, :string
      add :jobs, :map
      add :triggers, :map
      add :edges, :map

      timestamps(type: :utc_datetime_usec)
    end
  end
end
