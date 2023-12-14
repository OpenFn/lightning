defmodule Lightning.Repo.Migrations.AddScheduledDeletionToWorkflowEdges do
  use Ecto.Migration

  def change do
    alter table(:workflow_edges) do
      add(:scheduled_deletion, :utc_datetime)
    end
  end
end
