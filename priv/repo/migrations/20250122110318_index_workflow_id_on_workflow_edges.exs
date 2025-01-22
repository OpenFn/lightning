defmodule Lightning.Repo.Migrations.IndexWorkflowIdOnWorkflowEdges do
  use Ecto.Migration

  def change do
    create index(:workflow_edges, [:workflow_id])
  end
end
