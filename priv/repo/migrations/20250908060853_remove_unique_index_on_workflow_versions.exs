defmodule Lightning.Repo.Migrations.RemoveUniqueIndexOnWorkflowVersions do
  use Ecto.Migration

  def change do
    drop unique_index(:workflow_versions, [:workflow_id, :hash])
  end
end
