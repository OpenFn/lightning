defmodule Lightning.Repo.Migrations.IndexWorkflowIdOnWorkflowEdges do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:workflow_edges, [:workflow_id])
  end
end
