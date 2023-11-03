defmodule Lightning.Repo.Migrations.AddEnabledColumnToWorkflowEdges do
  use Ecto.Migration

  def change do
    alter table(:workflow_edges) do
      add :enabled, :boolean, null: false, default: true
    end
  end
end
