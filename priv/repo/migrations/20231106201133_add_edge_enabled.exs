defmodule Lightning.Repo.Migrations.AddEdgeEnabled do
  use Ecto.Migration

  def change do
    alter table(:workflow_edges) do
      add :enabled, :boolean, null: false, default: true
    end
  end
end
