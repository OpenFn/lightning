defmodule Lightning.Repo.Migrations.AddWorkflowsIndexes do
  use Ecto.Migration

  def change do
    create index(:work_orders, [:snapshot_id])
    create index(:workflows, [:project_id])
  end
end
